const std = @import("std");
pub const PERIPHERAL_BASE = 0x40000000;
pub const PERIPHERAL_BITBAND_BASE = 0x42000000;
pub fn Register(comptime R: type) type {
    return RegisterRW(R, R);
}

pub fn comptimeMaxInt(comptime T: type) comptime_int {
    const bit_count = @bitSizeOf(type);
    if (bit_count == 0) return 0;
    return (1 << (bit_count)) - 1;
}

pub fn RegisterRW(comptime Read: type, comptime Write: type) type {
    return struct {
        raw_ptr: *volatile u32,

        const Self = @This();

        pub fn init(address: usize) Self {
            return Self{ .raw_ptr = @intToPtr(*volatile u32, address) };
        }

        pub fn initRange(address: usize, comptime dim_increment: usize, comptime num_registers: usize) [num_registers]Self {
            var registers: [num_registers]Self = undefined;
            var i: usize = 0;
            while (i < num_registers) : (i += 1) {
                registers[i] = Self.init(address + (i * dim_increment));
            }
            return registers;
        }

        pub fn read(self: Self) Read {
            return @bitCast(Read, self.raw_ptr.*);
        }

        pub fn write(self: Self, value: Write) void {
            self.raw_ptr.* = @bitCast(u32, value);
        }

        pub fn modify(self: Self, new_value: anytype) void {
            if (Read != Write) {
                @compileError("Can't modify because read and write types for this register aren't the same.");
            }
            var old_value = self.read();
            const info = @typeInfo(@TypeOf(new_value));
            inline for (info.Struct.fields) |field| {
                @field(old_value, field.name) = @field(new_value, field.name);
            }
            self.write(old_value);
        }

        fn create_mask(self: Self, comptime T: type) u32 {
            var mask: u32 = 0;
            const info = @typeInfo(T);
            inline for (info.Struct.fields) |field| {
                mask |= comptimeMaxInt(field.field_type) << @bitOffsetOf(Read, field.name);
            }
            return mask;
        }

        fn create_value(self: Self, new_value: anytype) u32 {
            var value: u32 = 0;
            const info = @typeInfo(@TypeOf(new_value));
            inline for (info.Struct.fields) |field| {
                value |= @as(u32, @field(new_value, field.name)) << @bitOffsetOf(Read, field.name);
            }
            return value;
        }

        pub fn modify_mask(comptime self: Self, new_value: anytype) void {
            //self.modify(new_value);
            if (Read != Write) {
                @compileError("Can't modify because read and write types for this register aren't the same.");
            }
            var old_value = self.read();

            const mask: u32 = comptime self.create_mask(@TypeOf(new_value));
            const value: u32 = self.create_value(new_value);

            const updated: u32 = (@bitCast(u32, old_value) & ~mask) | value;
            self.write_raw(updated);
        }

        pub fn read_raw(self: Self) u32 {
            return self.raw_ptr.*;
        }

        pub fn write_raw(self: Self, value: u32) void {
            self.raw_ptr.* = value;
        }

        pub fn default_read_value(self: Self) Read {
            return Read{};
        }

        pub fn default_write_value(self: Self) Write {
            return Write{};
        }

        /// Get pointer to bitbanded peripheral register corresponding to the field
        /// Assumes that the reg_addr is within peripheral memory range
        /// Reference:
        /// Cortex-M3 Technical Reference Manual - 3.7 Bit Banding
        pub fn bitband_ptr(comptime self: Self, comptime field: []const u8) *volatile u32 {
            comptime {
                const field_type = @TypeOf(@field(Write{}, field));
                if (field_type != u1) {
                    @compileError("Can only bit-band access fields of type u1. Tried to access '" ++ field ++ ": " ++ @typeName(field_type) ++ "'");
                }
            }
            const reg_addr: usize = @ptrToInt(self.raw_ptr);
            const bit_offset = @bitOffsetOf(Write, field);
            const reg_offset = reg_addr - PERIPHERAL_BASE;
            comptime const bitband_addr = PERIPHERAL_BITBAND_BASE + reg_offset * 32 + bit_offset * 4;
            return @intToPtr(*volatile u32, bitband_addr);
        }

        /// Bit-banded write
        pub fn write_bit(comptime self: Self, comptime field: []const u8, value: u1) void {
            const ptr = comptime self.bitband_ptr(field);
            ptr.* = value;
        }

        /// Bit-banded read
        pub fn read_bit(comptime self: Self, comptime field: []const u8) u1 {
            const ptr = comptime self.bitband_ptr(field);
            return @intCast(u1, ptr.*);
        }
    };
}

pub fn RepeatedFields(comptime num_fields: usize, comptime field_name: []const u8, comptime T: type) type {
    var info = @typeInfo(packed struct { f: T });
    var fields: [num_fields]std.builtin.TypeInfo.StructField = undefined;
    var field_ix: usize = 0;
    while (field_ix < num_fields) : (field_ix += 1) {
        var field = info.Struct.fields[0];

        // awkward workaround for lack of comptime allocator
        @setEvalBranchQuota(100000);
        var field_ix_buffer: [field_name.len + 16]u8 = undefined;
        var stream = std.io.FixedBufferStream([]u8){ .buffer = &field_ix_buffer, .pos = 0 };
        std.fmt.format(stream.writer(), "{}{}", .{ field_name, field_ix }) catch unreachable;
        field.name = stream.getWritten();

        field.default_value = T.default_value;

        fields[field_ix] = field;
    }

    // TODO this might not be safe to set
    info.Struct.is_tuple = true;

    info.Struct.fields = &fields;
    return @Type(info);
}


///Flexible static memory controller
pub const fsmc = struct {

    //////////////////////////
    ///BCR1
    const bcr1_val = packed struct {
        ///MBKEN [0:0]
        ///MBKEN
        mbken: u1 = 0,
        ///MUXEN [1:1]
        ///MUXEN
        muxen: u1 = 0,
        ///MTYP [2:3]
        ///MTYP
        mtyp: u2 = 0,
        ///MWID [4:5]
        ///MWID
        mwid: u2 = 1,
        ///FACCEN [6:6]
        ///FACCEN
        faccen: u1 = 1,
        _unused7: u1 = 0,
        ///BURSTEN [8:8]
        ///BURSTEN
        bursten: u1 = 0,
        ///WAITPOL [9:9]
        ///WAITPOL
        waitpol: u1 = 0,
        _unused10: u1 = 0,
        ///WAITCFG [11:11]
        ///WAITCFG
        waitcfg: u1 = 0,
        ///WREN [12:12]
        ///WREN
        wren: u1 = 1,
        ///WAITEN [13:13]
        ///WAITEN
        waiten: u1 = 1,
        ///EXTMOD [14:14]
        ///EXTMOD
        extmod: u1 = 0,
        ///ASYNCWAIT [15:15]
        ///ASYNCWAIT
        asyncwait: u1 = 0,
        _unused16: u3 = 0,
        ///CBURSTRW [19:19]
        ///CBURSTRW
        cburstrw: u1 = 0,
        _unused20: u12 = 0,
    };
    ///SRAM/NOR-Flash chip-select control register
    ///1
    pub const bcr1 = Register(bcr1_val).init(0xA0000000 + 0x0);

    //////////////////////////
    ///BTR1
    const btr1_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        ///BUSTURN [16:19]
        ///BUSTURN
        busturn: u4 = 15,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 3,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash chip-select timing register
    ///1
    pub const btr1 = Register(btr1_val).init(0xA0000000 + 0x4);

    //////////////////////////
    ///BCR2
    const bcr2_val = packed struct {
        ///MBKEN [0:0]
        ///MBKEN
        mbken: u1 = 0,
        ///MUXEN [1:1]
        ///MUXEN
        muxen: u1 = 0,
        ///MTYP [2:3]
        ///MTYP
        mtyp: u2 = 0,
        ///MWID [4:5]
        ///MWID
        mwid: u2 = 1,
        ///FACCEN [6:6]
        ///FACCEN
        faccen: u1 = 1,
        _unused7: u1 = 0,
        ///BURSTEN [8:8]
        ///BURSTEN
        bursten: u1 = 0,
        ///WAITPOL [9:9]
        ///WAITPOL
        waitpol: u1 = 0,
        ///WRAPMOD [10:10]
        ///WRAPMOD
        wrapmod: u1 = 0,
        ///WAITCFG [11:11]
        ///WAITCFG
        waitcfg: u1 = 0,
        ///WREN [12:12]
        ///WREN
        wren: u1 = 1,
        ///WAITEN [13:13]
        ///WAITEN
        waiten: u1 = 1,
        ///EXTMOD [14:14]
        ///EXTMOD
        extmod: u1 = 0,
        ///ASYNCWAIT [15:15]
        ///ASYNCWAIT
        asyncwait: u1 = 0,
        _unused16: u3 = 0,
        ///CBURSTRW [19:19]
        ///CBURSTRW
        cburstrw: u1 = 0,
        _unused20: u12 = 0,
    };
    ///SRAM/NOR-Flash chip-select control register
    ///2
    pub const bcr2 = Register(bcr2_val).init(0xA0000000 + 0x8);

    //////////////////////////
    ///BTR2
    const btr2_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        ///BUSTURN [16:19]
        ///BUSTURN
        busturn: u4 = 15,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 3,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash chip-select timing register
    ///2
    pub const btr2 = Register(btr2_val).init(0xA0000000 + 0xC);

    //////////////////////////
    ///BCR3
    const bcr3_val = packed struct {
        ///MBKEN [0:0]
        ///MBKEN
        mbken: u1 = 0,
        ///MUXEN [1:1]
        ///MUXEN
        muxen: u1 = 0,
        ///MTYP [2:3]
        ///MTYP
        mtyp: u2 = 0,
        ///MWID [4:5]
        ///MWID
        mwid: u2 = 1,
        ///FACCEN [6:6]
        ///FACCEN
        faccen: u1 = 1,
        _unused7: u1 = 0,
        ///BURSTEN [8:8]
        ///BURSTEN
        bursten: u1 = 0,
        ///WAITPOL [9:9]
        ///WAITPOL
        waitpol: u1 = 0,
        ///WRAPMOD [10:10]
        ///WRAPMOD
        wrapmod: u1 = 0,
        ///WAITCFG [11:11]
        ///WAITCFG
        waitcfg: u1 = 0,
        ///WREN [12:12]
        ///WREN
        wren: u1 = 1,
        ///WAITEN [13:13]
        ///WAITEN
        waiten: u1 = 1,
        ///EXTMOD [14:14]
        ///EXTMOD
        extmod: u1 = 0,
        ///ASYNCWAIT [15:15]
        ///ASYNCWAIT
        asyncwait: u1 = 0,
        _unused16: u3 = 0,
        ///CBURSTRW [19:19]
        ///CBURSTRW
        cburstrw: u1 = 0,
        _unused20: u12 = 0,
    };
    ///SRAM/NOR-Flash chip-select control register
    ///3
    pub const bcr3 = Register(bcr3_val).init(0xA0000000 + 0x10);

    //////////////////////////
    ///BTR3
    const btr3_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        ///BUSTURN [16:19]
        ///BUSTURN
        busturn: u4 = 15,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 3,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash chip-select timing register
    ///3
    pub const btr3 = Register(btr3_val).init(0xA0000000 + 0x14);

    //////////////////////////
    ///BCR4
    const bcr4_val = packed struct {
        ///MBKEN [0:0]
        ///MBKEN
        mbken: u1 = 0,
        ///MUXEN [1:1]
        ///MUXEN
        muxen: u1 = 0,
        ///MTYP [2:3]
        ///MTYP
        mtyp: u2 = 0,
        ///MWID [4:5]
        ///MWID
        mwid: u2 = 1,
        ///FACCEN [6:6]
        ///FACCEN
        faccen: u1 = 1,
        _unused7: u1 = 0,
        ///BURSTEN [8:8]
        ///BURSTEN
        bursten: u1 = 0,
        ///WAITPOL [9:9]
        ///WAITPOL
        waitpol: u1 = 0,
        ///WRAPMOD [10:10]
        ///WRAPMOD
        wrapmod: u1 = 0,
        ///WAITCFG [11:11]
        ///WAITCFG
        waitcfg: u1 = 0,
        ///WREN [12:12]
        ///WREN
        wren: u1 = 1,
        ///WAITEN [13:13]
        ///WAITEN
        waiten: u1 = 1,
        ///EXTMOD [14:14]
        ///EXTMOD
        extmod: u1 = 0,
        ///ASYNCWAIT [15:15]
        ///ASYNCWAIT
        asyncwait: u1 = 0,
        _unused16: u3 = 0,
        ///CBURSTRW [19:19]
        ///CBURSTRW
        cburstrw: u1 = 0,
        _unused20: u12 = 0,
    };
    ///SRAM/NOR-Flash chip-select control register
    ///4
    pub const bcr4 = Register(bcr4_val).init(0xA0000000 + 0x18);

    //////////////////////////
    ///BTR4
    const btr4_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        ///BUSTURN [16:19]
        ///BUSTURN
        busturn: u4 = 15,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 3,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash chip-select timing register
    ///4
    pub const btr4 = Register(btr4_val).init(0xA0000000 + 0x1C);

    //////////////////////////
    ///PCR2
    const pcr2_val = packed struct {
        _unused0: u1 = 0,
        ///PWAITEN [1:1]
        ///PWAITEN
        pwaiten: u1 = 0,
        ///PBKEN [2:2]
        ///PBKEN
        pbken: u1 = 0,
        ///PTYP [3:3]
        ///PTYP
        ptyp: u1 = 1,
        ///PWID [4:5]
        ///PWID
        pwid: u2 = 1,
        ///ECCEN [6:6]
        ///ECCEN
        eccen: u1 = 0,
        _unused7: u2 = 0,
        ///TCLR [9:12]
        ///TCLR
        tclr: u4 = 0,
        ///TAR [13:16]
        ///TAR
        tar: u4 = 0,
        ///ECCPS [17:19]
        ///ECCPS
        eccps: u3 = 0,
        _unused20: u12 = 0,
    };
    ///PC Card/NAND Flash control register
    ///2
    pub const pcr2 = Register(pcr2_val).init(0xA0000000 + 0x60);

    //////////////////////////
    ///SR2
    const sr2_val = packed struct {
        ///IRS [0:0]
        ///IRS
        irs: u1 = 0,
        ///ILS [1:1]
        ///ILS
        ils: u1 = 0,
        ///IFS [2:2]
        ///IFS
        ifs: u1 = 0,
        ///IREN [3:3]
        ///IREN
        iren: u1 = 0,
        ///ILEN [4:4]
        ///ILEN
        ilen: u1 = 0,
        ///IFEN [5:5]
        ///IFEN
        ifen: u1 = 0,
        ///FEMPT [6:6]
        ///FEMPT
        fempt: u1 = 1,
        _unused7: u25 = 0,
    };
    ///FIFO status and interrupt register
    ///2
    pub const sr2 = Register(sr2_val).init(0xA0000000 + 0x64);

    //////////////////////////
    ///PMEM2
    const pmem2_val = packed struct {
        ///MEMSETx [0:7]
        ///MEMSETx
        memsetx: u8 = 252,
        ///MEMWAITx [8:15]
        ///MEMWAITx
        memwaitx: u8 = 252,
        ///MEMHOLDx [16:23]
        ///MEMHOLDx
        memholdx: u8 = 252,
        ///MEMHIZx [24:31]
        ///MEMHIZx
        memhizx: u8 = 252,
    };
    ///Common memory space timing register
    ///2
    pub const pmem2 = Register(pmem2_val).init(0xA0000000 + 0x68);

    //////////////////////////
    ///PATT2
    const patt2_val = packed struct {
        ///ATTSETx [0:7]
        ///Attribute memory x setup
        ///time
        attsetx: u8 = 252,
        ///ATTWAITx [8:15]
        ///Attribute memory x wait
        ///time
        attwaitx: u8 = 252,
        ///ATTHOLDx [16:23]
        ///Attribute memory x hold
        ///time
        attholdx: u8 = 252,
        ///ATTHIZx [24:31]
        ///Attribute memory x databus HiZ
        ///time
        atthizx: u8 = 252,
    };
    ///Attribute memory space timing register
    ///2
    pub const patt2 = Register(patt2_val).init(0xA0000000 + 0x6C);

    //////////////////////////
    ///ECCR2
    const eccr2_val = packed struct {
        ///ECCx [0:31]
        ///ECC result
        eccx: u32 = 0,
    };
    ///ECC result register 2
    pub const eccr2 = RegisterRW(eccr2_val, void).init(0xA0000000 + 0x74);

    //////////////////////////
    ///PCR3
    const pcr3_val = packed struct {
        _unused0: u1 = 0,
        ///PWAITEN [1:1]
        ///PWAITEN
        pwaiten: u1 = 0,
        ///PBKEN [2:2]
        ///PBKEN
        pbken: u1 = 0,
        ///PTYP [3:3]
        ///PTYP
        ptyp: u1 = 1,
        ///PWID [4:5]
        ///PWID
        pwid: u2 = 1,
        ///ECCEN [6:6]
        ///ECCEN
        eccen: u1 = 0,
        _unused7: u2 = 0,
        ///TCLR [9:12]
        ///TCLR
        tclr: u4 = 0,
        ///TAR [13:16]
        ///TAR
        tar: u4 = 0,
        ///ECCPS [17:19]
        ///ECCPS
        eccps: u3 = 0,
        _unused20: u12 = 0,
    };
    ///PC Card/NAND Flash control register
    ///3
    pub const pcr3 = Register(pcr3_val).init(0xA0000000 + 0x80);

    //////////////////////////
    ///SR3
    const sr3_val = packed struct {
        ///IRS [0:0]
        ///IRS
        irs: u1 = 0,
        ///ILS [1:1]
        ///ILS
        ils: u1 = 0,
        ///IFS [2:2]
        ///IFS
        ifs: u1 = 0,
        ///IREN [3:3]
        ///IREN
        iren: u1 = 0,
        ///ILEN [4:4]
        ///ILEN
        ilen: u1 = 0,
        ///IFEN [5:5]
        ///IFEN
        ifen: u1 = 0,
        ///FEMPT [6:6]
        ///FEMPT
        fempt: u1 = 1,
        _unused7: u25 = 0,
    };
    ///FIFO status and interrupt register
    ///3
    pub const sr3 = Register(sr3_val).init(0xA0000000 + 0x84);

    //////////////////////////
    ///PMEM3
    const pmem3_val = packed struct {
        ///MEMSETx [0:7]
        ///MEMSETx
        memsetx: u8 = 252,
        ///MEMWAITx [8:15]
        ///MEMWAITx
        memwaitx: u8 = 252,
        ///MEMHOLDx [16:23]
        ///MEMHOLDx
        memholdx: u8 = 252,
        ///MEMHIZx [24:31]
        ///MEMHIZx
        memhizx: u8 = 252,
    };
    ///Common memory space timing register
    ///3
    pub const pmem3 = Register(pmem3_val).init(0xA0000000 + 0x88);

    //////////////////////////
    ///PATT3
    const patt3_val = packed struct {
        ///ATTSETx [0:7]
        ///ATTSETx
        attsetx: u8 = 252,
        ///ATTWAITx [8:15]
        ///ATTWAITx
        attwaitx: u8 = 252,
        ///ATTHOLDx [16:23]
        ///ATTHOLDx
        attholdx: u8 = 252,
        ///ATTHIZx [24:31]
        ///ATTHIZx
        atthizx: u8 = 252,
    };
    ///Attribute memory space timing register
    ///3
    pub const patt3 = Register(patt3_val).init(0xA0000000 + 0x8C);

    //////////////////////////
    ///ECCR3
    const eccr3_val = packed struct {
        ///ECCx [0:31]
        ///ECCx
        eccx: u32 = 0,
    };
    ///ECC result register 3
    pub const eccr3 = RegisterRW(eccr3_val, void).init(0xA0000000 + 0x94);

    //////////////////////////
    ///PCR4
    const pcr4_val = packed struct {
        _unused0: u1 = 0,
        ///PWAITEN [1:1]
        ///PWAITEN
        pwaiten: u1 = 0,
        ///PBKEN [2:2]
        ///PBKEN
        pbken: u1 = 0,
        ///PTYP [3:3]
        ///PTYP
        ptyp: u1 = 1,
        ///PWID [4:5]
        ///PWID
        pwid: u2 = 1,
        ///ECCEN [6:6]
        ///ECCEN
        eccen: u1 = 0,
        _unused7: u2 = 0,
        ///TCLR [9:12]
        ///TCLR
        tclr: u4 = 0,
        ///TAR [13:16]
        ///TAR
        tar: u4 = 0,
        ///ECCPS [17:19]
        ///ECCPS
        eccps: u3 = 0,
        _unused20: u12 = 0,
    };
    ///PC Card/NAND Flash control register
    ///4
    pub const pcr4 = Register(pcr4_val).init(0xA0000000 + 0xA0);

    //////////////////////////
    ///SR4
    const sr4_val = packed struct {
        ///IRS [0:0]
        ///IRS
        irs: u1 = 0,
        ///ILS [1:1]
        ///ILS
        ils: u1 = 0,
        ///IFS [2:2]
        ///IFS
        ifs: u1 = 0,
        ///IREN [3:3]
        ///IREN
        iren: u1 = 0,
        ///ILEN [4:4]
        ///ILEN
        ilen: u1 = 0,
        ///IFEN [5:5]
        ///IFEN
        ifen: u1 = 0,
        ///FEMPT [6:6]
        ///FEMPT
        fempt: u1 = 1,
        _unused7: u25 = 0,
    };
    ///FIFO status and interrupt register
    ///4
    pub const sr4 = Register(sr4_val).init(0xA0000000 + 0xA4);

    //////////////////////////
    ///PMEM4
    const pmem4_val = packed struct {
        ///MEMSETx [0:7]
        ///MEMSETx
        memsetx: u8 = 252,
        ///MEMWAITx [8:15]
        ///MEMWAITx
        memwaitx: u8 = 252,
        ///MEMHOLDx [16:23]
        ///MEMHOLDx
        memholdx: u8 = 252,
        ///MEMHIZx [24:31]
        ///MEMHIZx
        memhizx: u8 = 252,
    };
    ///Common memory space timing register
    ///4
    pub const pmem4 = Register(pmem4_val).init(0xA0000000 + 0xA8);

    //////////////////////////
    ///PATT4
    const patt4_val = packed struct {
        ///ATTSETx [0:7]
        ///ATTSETx
        attsetx: u8 = 252,
        ///ATTWAITx [8:15]
        ///ATTWAITx
        attwaitx: u8 = 252,
        ///ATTHOLDx [16:23]
        ///ATTHOLDx
        attholdx: u8 = 252,
        ///ATTHIZx [24:31]
        ///ATTHIZx
        atthizx: u8 = 252,
    };
    ///Attribute memory space timing register
    ///4
    pub const patt4 = Register(patt4_val).init(0xA0000000 + 0xAC);

    //////////////////////////
    ///PIO4
    const pio4_val = packed struct {
        ///IOSETx [0:7]
        ///IOSETx
        iosetx: u8 = 252,
        ///IOWAITx [8:15]
        ///IOWAITx
        iowaitx: u8 = 252,
        ///IOHOLDx [16:23]
        ///IOHOLDx
        ioholdx: u8 = 252,
        ///IOHIZx [24:31]
        ///IOHIZx
        iohizx: u8 = 252,
    };
    ///I/O space timing register 4
    pub const pio4 = Register(pio4_val).init(0xA0000000 + 0xB0);

    //////////////////////////
    ///BWTR1
    const bwtr1_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        _unused16: u4 = 0,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 0,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash write timing registers
    ///1
    pub const bwtr1 = Register(bwtr1_val).init(0xA0000000 + 0x104);

    //////////////////////////
    ///BWTR2
    const bwtr2_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        _unused16: u4 = 0,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 0,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash write timing registers
    ///2
    pub const bwtr2 = Register(bwtr2_val).init(0xA0000000 + 0x10C);

    //////////////////////////
    ///BWTR3
    const bwtr3_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        _unused16: u4 = 0,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 0,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash write timing registers
    ///3
    pub const bwtr3 = Register(bwtr3_val).init(0xA0000000 + 0x114);

    //////////////////////////
    ///BWTR4
    const bwtr4_val = packed struct {
        ///ADDSET [0:3]
        ///ADDSET
        addset: u4 = 15,
        ///ADDHLD [4:7]
        ///ADDHLD
        addhld: u4 = 15,
        ///DATAST [8:15]
        ///DATAST
        datast: u8 = 255,
        _unused16: u4 = 0,
        ///CLKDIV [20:23]
        ///CLKDIV
        clkdiv: u4 = 15,
        ///DATLAT [24:27]
        ///DATLAT
        datlat: u4 = 15,
        ///ACCMOD [28:29]
        ///ACCMOD
        accmod: u2 = 0,
        _unused30: u2 = 0,
    };
    ///SRAM/NOR-Flash write timing registers
    ///4
    pub const bwtr4 = Register(bwtr4_val).init(0xA0000000 + 0x11C);
};

///Power control
pub const pwr = struct {

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///LPDS [0:0]
        ///Low Power Deep Sleep
        lpds: u1 = 0,
        ///PDDS [1:1]
        ///Power Down Deep Sleep
        pdds: u1 = 0,
        ///CWUF [2:2]
        ///Clear Wake-up Flag
        cwuf: u1 = 0,
        ///CSBF [3:3]
        ///Clear STANDBY Flag
        csbf: u1 = 0,
        ///PVDE [4:4]
        ///Power Voltage Detector
        ///Enable
        pvde: u1 = 0,
        ///PLS [5:7]
        ///PVD Level Selection
        pls: u3 = 0,
        ///DBP [8:8]
        ///Disable Backup Domain write
        ///protection
        dbp: u1 = 0,
        _unused9: u23 = 0,
    };
    ///Power control register
    ///(PWR_CR)
    pub const cr = Register(cr_val).init(0x40007000 + 0x0);

    //////////////////////////
    ///CSR
    const csr_val = packed struct {
        ///WUF [0:0]
        ///Wake-Up Flag
        wuf: u1 = 0,
        ///SBF [1:1]
        ///STANDBY Flag
        sbf: u1 = 0,
        ///PVDO [2:2]
        ///PVD Output
        pvdo: u1 = 0,
        _unused3: u5 = 0,
        ///EWUP [8:8]
        ///Enable WKUP pin
        ewup: u1 = 0,
        _unused9: u23 = 0,
    };
    ///Power control register
    ///(PWR_CR)
    pub const csr = Register(csr_val).init(0x40007000 + 0x4);
};

///Reset and clock control
pub const rcc = struct {

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///HSION [0:0]
        ///Internal High Speed clock
        ///enable
        hsion: u1 = 1,
        ///HSIRDY [1:1]
        ///Internal High Speed clock ready
        ///flag
        hsirdy: u1 = 1,
        _unused2: u1 = 0,
        ///HSITRIM [3:7]
        ///Internal High Speed clock
        ///trimming
        hsitrim: u5 = 16,
        ///HSICAL [8:15]
        ///Internal High Speed clock
        ///Calibration
        hsical: u8 = 0,
        ///HSEON [16:16]
        ///External High Speed clock
        ///enable
        hseon: u1 = 0,
        ///HSERDY [17:17]
        ///External High Speed clock ready
        ///flag
        hserdy: u1 = 0,
        ///HSEBYP [18:18]
        ///External High Speed clock
        ///Bypass
        hsebyp: u1 = 0,
        ///CSSON [19:19]
        ///Clock Security System
        ///enable
        csson: u1 = 0,
        _unused20: u4 = 0,
        ///PLLON [24:24]
        ///PLL enable
        pllon: u1 = 0,
        ///PLLRDY [25:25]
        ///PLL clock ready flag
        pllrdy: u1 = 0,
        _unused26: u6 = 0,
    };
    ///Clock control register
    pub const cr = Register(cr_val).init(0x40021000 + 0x0);

    //////////////////////////
    ///CFGR
    const cfgr_val = packed struct {
        ///SW [0:1]
        ///System clock Switch
        sw: u2 = 0,
        ///SWS [2:3]
        ///System Clock Switch Status
        sws: u2 = 0,
        ///HPRE [4:7]
        ///AHB prescaler
        hpre: u4 = 0,
        ///PPRE1 [8:10]
        ///APB Low speed prescaler
        ///(APB1)
        ppre1: u3 = 0,
        ///PPRE2 [11:13]
        ///APB High speed prescaler
        ///(APB2)
        ppre2: u3 = 0,
        ///ADCPRE [14:15]
        ///ADC prescaler
        adcpre: u2 = 0,
        ///PLLSRC [16:16]
        ///PLL entry clock source
        pllsrc: u1 = 0,
        ///PLLXTPRE [17:17]
        ///HSE divider for PLL entry
        pllxtpre: u1 = 0,
        ///PLLMUL [18:21]
        ///PLL Multiplication Factor
        pllmul: u4 = 0,
        ///OTGFSPRE [22:22]
        ///USB OTG FS prescaler
        otgfspre: u1 = 0,
        _unused23: u1 = 0,
        ///MCO [24:26]
        ///Microcontroller clock
        ///output
        mco: u3 = 0,
        _unused27: u5 = 0,
    };
    ///Clock configuration register
    ///(RCC_CFGR)
    pub const cfgr = Register(cfgr_val).init(0x40021000 + 0x4);

    //////////////////////////
    ///CIR
    const cir_val = packed struct {
        ///LSIRDYF [0:0]
        ///LSI Ready Interrupt flag
        lsirdyf: u1 = 0,
        ///LSERDYF [1:1]
        ///LSE Ready Interrupt flag
        lserdyf: u1 = 0,
        ///HSIRDYF [2:2]
        ///HSI Ready Interrupt flag
        hsirdyf: u1 = 0,
        ///HSERDYF [3:3]
        ///HSE Ready Interrupt flag
        hserdyf: u1 = 0,
        ///PLLRDYF [4:4]
        ///PLL Ready Interrupt flag
        pllrdyf: u1 = 0,
        _unused5: u2 = 0,
        ///CSSF [7:7]
        ///Clock Security System Interrupt
        ///flag
        cssf: u1 = 0,
        ///LSIRDYIE [8:8]
        ///LSI Ready Interrupt Enable
        lsirdyie: u1 = 0,
        ///LSERDYIE [9:9]
        ///LSE Ready Interrupt Enable
        lserdyie: u1 = 0,
        ///HSIRDYIE [10:10]
        ///HSI Ready Interrupt Enable
        hsirdyie: u1 = 0,
        ///HSERDYIE [11:11]
        ///HSE Ready Interrupt Enable
        hserdyie: u1 = 0,
        ///PLLRDYIE [12:12]
        ///PLL Ready Interrupt Enable
        pllrdyie: u1 = 0,
        _unused13: u3 = 0,
        ///LSIRDYC [16:16]
        ///LSI Ready Interrupt Clear
        lsirdyc: u1 = 0,
        ///LSERDYC [17:17]
        ///LSE Ready Interrupt Clear
        lserdyc: u1 = 0,
        ///HSIRDYC [18:18]
        ///HSI Ready Interrupt Clear
        hsirdyc: u1 = 0,
        ///HSERDYC [19:19]
        ///HSE Ready Interrupt Clear
        hserdyc: u1 = 0,
        ///PLLRDYC [20:20]
        ///PLL Ready Interrupt Clear
        pllrdyc: u1 = 0,
        _unused21: u2 = 0,
        ///CSSC [23:23]
        ///Clock security system interrupt
        ///clear
        cssc: u1 = 0,
        _unused24: u8 = 0,
    };
    ///Clock interrupt register
    ///(RCC_CIR)
    pub const cir = Register(cir_val).init(0x40021000 + 0x8);

    //////////////////////////
    ///APB2RSTR
    const apb2rstr_val = packed struct {
        ///AFIORST [0:0]
        ///Alternate function I/O
        ///reset
        afiorst: u1 = 0,
        _unused1: u1 = 0,
        ///IOPARST [2:2]
        ///IO port A reset
        ioparst: u1 = 0,
        ///IOPBRST [3:3]
        ///IO port B reset
        iopbrst: u1 = 0,
        ///IOPCRST [4:4]
        ///IO port C reset
        iopcrst: u1 = 0,
        ///IOPDRST [5:5]
        ///IO port D reset
        iopdrst: u1 = 0,
        ///IOPERST [6:6]
        ///IO port E reset
        ioperst: u1 = 0,
        ///IOPFRST [7:7]
        ///IO port F reset
        iopfrst: u1 = 0,
        ///IOPGRST [8:8]
        ///IO port G reset
        iopgrst: u1 = 0,
        ///ADC1RST [9:9]
        ///ADC 1 interface reset
        adc1rst: u1 = 0,
        ///ADC2RST [10:10]
        ///ADC 2 interface reset
        adc2rst: u1 = 0,
        ///TIM1RST [11:11]
        ///TIM1 timer reset
        tim1rst: u1 = 0,
        ///SPI1RST [12:12]
        ///SPI 1 reset
        spi1rst: u1 = 0,
        ///TIM8RST [13:13]
        ///TIM8 timer reset
        tim8rst: u1 = 0,
        ///USART1RST [14:14]
        ///USART1 reset
        usart1rst: u1 = 0,
        ///ADC3RST [15:15]
        ///ADC 3 interface reset
        adc3rst: u1 = 0,
        _unused16: u3 = 0,
        ///TIM9RST [19:19]
        ///TIM9 timer reset
        tim9rst: u1 = 0,
        ///TIM10RST [20:20]
        ///TIM10 timer reset
        tim10rst: u1 = 0,
        ///TIM11RST [21:21]
        ///TIM11 timer reset
        tim11rst: u1 = 0,
        _unused22: u10 = 0,
    };
    ///APB2 peripheral reset register
    ///(RCC_APB2RSTR)
    pub const apb2rstr = Register(apb2rstr_val).init(0x40021000 + 0xC);

    //////////////////////////
    ///APB1RSTR
    const apb1rstr_val = packed struct {
        ///TIM2RST [0:0]
        ///Timer 2 reset
        tim2rst: u1 = 0,
        ///TIM3RST [1:1]
        ///Timer 3 reset
        tim3rst: u1 = 0,
        ///TIM4RST [2:2]
        ///Timer 4 reset
        tim4rst: u1 = 0,
        ///TIM5RST [3:3]
        ///Timer 5 reset
        tim5rst: u1 = 0,
        ///TIM6RST [4:4]
        ///Timer 6 reset
        tim6rst: u1 = 0,
        ///TIM7RST [5:5]
        ///Timer 7 reset
        tim7rst: u1 = 0,
        ///TIM12RST [6:6]
        ///Timer 12 reset
        tim12rst: u1 = 0,
        ///TIM13RST [7:7]
        ///Timer 13 reset
        tim13rst: u1 = 0,
        ///TIM14RST [8:8]
        ///Timer 14 reset
        tim14rst: u1 = 0,
        _unused9: u2 = 0,
        ///WWDGRST [11:11]
        ///Window watchdog reset
        wwdgrst: u1 = 0,
        _unused12: u2 = 0,
        ///SPI2RST [14:14]
        ///SPI2 reset
        spi2rst: u1 = 0,
        ///SPI3RST [15:15]
        ///SPI3 reset
        spi3rst: u1 = 0,
        _unused16: u1 = 0,
        ///USART2RST [17:17]
        ///USART 2 reset
        usart2rst: u1 = 0,
        ///USART3RST [18:18]
        ///USART 3 reset
        usart3rst: u1 = 0,
        ///UART4RST [19:19]
        ///UART 4 reset
        uart4rst: u1 = 0,
        ///UART5RST [20:20]
        ///UART 5 reset
        uart5rst: u1 = 0,
        ///I2C1RST [21:21]
        ///I2C1 reset
        i2c1rst: u1 = 0,
        ///I2C2RST [22:22]
        ///I2C2 reset
        i2c2rst: u1 = 0,
        ///USBRST [23:23]
        ///USB reset
        usbrst: u1 = 0,
        _unused24: u1 = 0,
        ///CANRST [25:25]
        ///CAN reset
        canrst: u1 = 0,
        _unused26: u1 = 0,
        ///BKPRST [27:27]
        ///Backup interface reset
        bkprst: u1 = 0,
        ///PWRRST [28:28]
        ///Power interface reset
        pwrrst: u1 = 0,
        ///DACRST [29:29]
        ///DAC interface reset
        dacrst: u1 = 0,
        _unused30: u2 = 0,
    };
    ///APB1 peripheral reset register
    ///(RCC_APB1RSTR)
    pub const apb1rstr = Register(apb1rstr_val).init(0x40021000 + 0x10);

    //////////////////////////
    ///AHBENR
    const ahbenr_val = packed struct {
        ///DMA1EN [0:0]
        ///DMA1 clock enable
        dma1en: u1 = 0,
        ///DMA2EN [1:1]
        ///DMA2 clock enable
        dma2en: u1 = 0,
        ///SRAMEN [2:2]
        ///SRAM interface clock
        ///enable
        sramen: u1 = 1,
        _unused3: u1 = 0,
        ///FLITFEN [4:4]
        ///FLITF clock enable
        flitfen: u1 = 1,
        _unused5: u1 = 0,
        ///CRCEN [6:6]
        ///CRC clock enable
        crcen: u1 = 0,
        _unused7: u1 = 0,
        ///FSMCEN [8:8]
        ///FSMC clock enable
        fsmcen: u1 = 0,
        _unused9: u1 = 0,
        ///SDIOEN [10:10]
        ///SDIO clock enable
        sdioen: u1 = 0,
        _unused11: u21 = 0,
    };
    ///AHB Peripheral Clock enable register
    ///(RCC_AHBENR)
    pub const ahbenr = Register(ahbenr_val).init(0x40021000 + 0x14);

    //////////////////////////
    ///APB2ENR
    const apb2enr_val = packed struct {
        ///AFIOEN [0:0]
        ///Alternate function I/O clock
        ///enable
        afioen: u1 = 0,
        _unused1: u1 = 0,
        ///IOPAEN [2:2]
        ///I/O port A clock enable
        iopaen: u1 = 0,
        ///IOPBEN [3:3]
        ///I/O port B clock enable
        iopben: u1 = 0,
        ///IOPCEN [4:4]
        ///I/O port C clock enable
        iopcen: u1 = 0,
        ///IOPDEN [5:5]
        ///I/O port D clock enable
        iopden: u1 = 0,
        ///IOPEEN [6:6]
        ///I/O port E clock enable
        iopeen: u1 = 0,
        ///IOPFEN [7:7]
        ///I/O port F clock enable
        iopfen: u1 = 0,
        ///IOPGEN [8:8]
        ///I/O port G clock enable
        iopgen: u1 = 0,
        ///ADC1EN [9:9]
        ///ADC 1 interface clock
        ///enable
        adc1en: u1 = 0,
        ///ADC2EN [10:10]
        ///ADC 2 interface clock
        ///enable
        adc2en: u1 = 0,
        ///TIM1EN [11:11]
        ///TIM1 Timer clock enable
        tim1en: u1 = 0,
        ///SPI1EN [12:12]
        ///SPI 1 clock enable
        spi1en: u1 = 0,
        ///TIM8EN [13:13]
        ///TIM8 Timer clock enable
        tim8en: u1 = 0,
        ///USART1EN [14:14]
        ///USART1 clock enable
        usart1en: u1 = 0,
        ///ADC3EN [15:15]
        ///ADC3 interface clock
        ///enable
        adc3en: u1 = 0,
        _unused16: u3 = 0,
        ///TIM9EN [19:19]
        ///TIM9 Timer clock enable
        tim9en: u1 = 0,
        ///TIM10EN [20:20]
        ///TIM10 Timer clock enable
        tim10en: u1 = 0,
        ///TIM11EN [21:21]
        ///TIM11 Timer clock enable
        tim11en: u1 = 0,
        _unused22: u10 = 0,
    };
    ///APB2 peripheral clock enable register
    ///(RCC_APB2ENR)
    pub const apb2enr = Register(apb2enr_val).init(0x40021000 + 0x18);

    //////////////////////////
    ///APB1ENR
    const apb1enr_val = packed struct {
        ///TIM2EN [0:0]
        ///Timer 2 clock enable
        tim2en: u1 = 0,
        ///TIM3EN [1:1]
        ///Timer 3 clock enable
        tim3en: u1 = 0,
        ///TIM4EN [2:2]
        ///Timer 4 clock enable
        tim4en: u1 = 0,
        ///TIM5EN [3:3]
        ///Timer 5 clock enable
        tim5en: u1 = 0,
        ///TIM6EN [4:4]
        ///Timer 6 clock enable
        tim6en: u1 = 0,
        ///TIM7EN [5:5]
        ///Timer 7 clock enable
        tim7en: u1 = 0,
        ///TIM12EN [6:6]
        ///Timer 12 clock enable
        tim12en: u1 = 0,
        ///TIM13EN [7:7]
        ///Timer 13 clock enable
        tim13en: u1 = 0,
        ///TIM14EN [8:8]
        ///Timer 14 clock enable
        tim14en: u1 = 0,
        _unused9: u2 = 0,
        ///WWDGEN [11:11]
        ///Window watchdog clock
        ///enable
        wwdgen: u1 = 0,
        _unused12: u2 = 0,
        ///SPI2EN [14:14]
        ///SPI 2 clock enable
        spi2en: u1 = 0,
        ///SPI3EN [15:15]
        ///SPI 3 clock enable
        spi3en: u1 = 0,
        _unused16: u1 = 0,
        ///USART2EN [17:17]
        ///USART 2 clock enable
        usart2en: u1 = 0,
        ///USART3EN [18:18]
        ///USART 3 clock enable
        usart3en: u1 = 0,
        ///UART4EN [19:19]
        ///UART 4 clock enable
        uart4en: u1 = 0,
        ///UART5EN [20:20]
        ///UART 5 clock enable
        uart5en: u1 = 0,
        ///I2C1EN [21:21]
        ///I2C 1 clock enable
        i2c1en: u1 = 0,
        ///I2C2EN [22:22]
        ///I2C 2 clock enable
        i2c2en: u1 = 0,
        ///USBEN [23:23]
        ///USB clock enable
        usben: u1 = 0,
        _unused24: u1 = 0,
        ///CANEN [25:25]
        ///CAN clock enable
        canen: u1 = 0,
        _unused26: u1 = 0,
        ///BKPEN [27:27]
        ///Backup interface clock
        ///enable
        bkpen: u1 = 0,
        ///PWREN [28:28]
        ///Power interface clock
        ///enable
        pwren: u1 = 0,
        ///DACEN [29:29]
        ///DAC interface clock enable
        dacen: u1 = 0,
        _unused30: u2 = 0,
    };
    ///APB1 peripheral clock enable register
    ///(RCC_APB1ENR)
    pub const apb1enr = Register(apb1enr_val).init(0x40021000 + 0x1C);

    //////////////////////////
    ///BDCR
    const bdcr_val = packed struct {
        ///LSEON [0:0]
        ///External Low Speed oscillator
        ///enable
        lseon: u1 = 0,
        ///LSERDY [1:1]
        ///External Low Speed oscillator
        ///ready
        lserdy: u1 = 0,
        ///LSEBYP [2:2]
        ///External Low Speed oscillator
        ///bypass
        lsebyp: u1 = 0,
        _unused3: u5 = 0,
        ///RTCSEL [8:9]
        ///RTC clock source selection
        rtcsel: u2 = 0,
        _unused10: u5 = 0,
        ///RTCEN [15:15]
        ///RTC clock enable
        rtcen: u1 = 0,
        ///BDRST [16:16]
        ///Backup domain software
        ///reset
        bdrst: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Backup domain control register
    ///(RCC_BDCR)
    pub const bdcr = Register(bdcr_val).init(0x40021000 + 0x20);

    //////////////////////////
    ///CSR
    const csr_val = packed struct {
        ///LSION [0:0]
        ///Internal low speed oscillator
        ///enable
        lsion: u1 = 0,
        ///LSIRDY [1:1]
        ///Internal low speed oscillator
        ///ready
        lsirdy: u1 = 0,
        _unused2: u22 = 0,
        ///RMVF [24:24]
        ///Remove reset flag
        rmvf: u1 = 0,
        _unused25: u1 = 0,
        ///PINRSTF [26:26]
        ///PIN reset flag
        pinrstf: u1 = 1,
        ///PORRSTF [27:27]
        ///POR/PDR reset flag
        porrstf: u1 = 1,
        ///SFTRSTF [28:28]
        ///Software reset flag
        sftrstf: u1 = 0,
        ///IWDGRSTF [29:29]
        ///Independent watchdog reset
        ///flag
        iwdgrstf: u1 = 0,
        ///WWDGRSTF [30:30]
        ///Window watchdog reset flag
        wwdgrstf: u1 = 0,
        ///LPWRRSTF [31:31]
        ///Low-power reset flag
        lpwrrstf: u1 = 0,
    };
    ///Control/status register
    ///(RCC_CSR)
    pub const csr = Register(csr_val).init(0x40021000 + 0x24);
};

///General purpose I/O
pub const gpioa = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40010800 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40010800 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40010800 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40010800 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40010800 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40010800 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40010800 + 0x18);
};

///General purpose I/O
pub const gpiob = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40010C00 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40010C00 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40010C00 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40010C00 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40010C00 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40010C00 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40010C00 + 0x18);
};

///General purpose I/O
pub const gpioc = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40011000 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40011000 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40011000 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40011000 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40011000 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40011000 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40011000 + 0x18);
};

///General purpose I/O
pub const gpiod = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40011400 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40011400 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40011400 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40011400 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40011400 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40011400 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40011400 + 0x18);
};

///General purpose I/O
pub const gpioe = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40011800 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40011800 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40011800 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40011800 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40011800 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40011800 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40011800 + 0x18);
};

///General purpose I/O
pub const gpiof = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40011C00 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40011C00 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40011C00 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40011C00 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40011C00 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40011C00 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40011C00 + 0x18);
};

///General purpose I/O
pub const gpiog = struct {

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///MODE0 [0:1]
        ///Port n.0 mode bits
        mode0: u2 = 0,
        ///CNF0 [2:3]
        ///Port n.0 configuration
        ///bits
        cnf0: u2 = 1,
        ///MODE1 [4:5]
        ///Port n.1 mode bits
        mode1: u2 = 0,
        ///CNF1 [6:7]
        ///Port n.1 configuration
        ///bits
        cnf1: u2 = 1,
        ///MODE2 [8:9]
        ///Port n.2 mode bits
        mode2: u2 = 0,
        ///CNF2 [10:11]
        ///Port n.2 configuration
        ///bits
        cnf2: u2 = 1,
        ///MODE3 [12:13]
        ///Port n.3 mode bits
        mode3: u2 = 0,
        ///CNF3 [14:15]
        ///Port n.3 configuration
        ///bits
        cnf3: u2 = 1,
        ///MODE4 [16:17]
        ///Port n.4 mode bits
        mode4: u2 = 0,
        ///CNF4 [18:19]
        ///Port n.4 configuration
        ///bits
        cnf4: u2 = 1,
        ///MODE5 [20:21]
        ///Port n.5 mode bits
        mode5: u2 = 0,
        ///CNF5 [22:23]
        ///Port n.5 configuration
        ///bits
        cnf5: u2 = 1,
        ///MODE6 [24:25]
        ///Port n.6 mode bits
        mode6: u2 = 0,
        ///CNF6 [26:27]
        ///Port n.6 configuration
        ///bits
        cnf6: u2 = 1,
        ///MODE7 [28:29]
        ///Port n.7 mode bits
        mode7: u2 = 0,
        ///CNF7 [30:31]
        ///Port n.7 configuration
        ///bits
        cnf7: u2 = 1,
    };
    ///Port configuration register low
    ///(GPIOn_CRL)
    pub const crl = Register(crl_val).init(0x40012000 + 0x0);

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///MODE8 [0:1]
        ///Port n.8 mode bits
        mode8: u2 = 0,
        ///CNF8 [2:3]
        ///Port n.8 configuration
        ///bits
        cnf8: u2 = 1,
        ///MODE9 [4:5]
        ///Port n.9 mode bits
        mode9: u2 = 0,
        ///CNF9 [6:7]
        ///Port n.9 configuration
        ///bits
        cnf9: u2 = 1,
        ///MODE10 [8:9]
        ///Port n.10 mode bits
        mode10: u2 = 0,
        ///CNF10 [10:11]
        ///Port n.10 configuration
        ///bits
        cnf10: u2 = 1,
        ///MODE11 [12:13]
        ///Port n.11 mode bits
        mode11: u2 = 0,
        ///CNF11 [14:15]
        ///Port n.11 configuration
        ///bits
        cnf11: u2 = 1,
        ///MODE12 [16:17]
        ///Port n.12 mode bits
        mode12: u2 = 0,
        ///CNF12 [18:19]
        ///Port n.12 configuration
        ///bits
        cnf12: u2 = 1,
        ///MODE13 [20:21]
        ///Port n.13 mode bits
        mode13: u2 = 0,
        ///CNF13 [22:23]
        ///Port n.13 configuration
        ///bits
        cnf13: u2 = 1,
        ///MODE14 [24:25]
        ///Port n.14 mode bits
        mode14: u2 = 0,
        ///CNF14 [26:27]
        ///Port n.14 configuration
        ///bits
        cnf14: u2 = 1,
        ///MODE15 [28:29]
        ///Port n.15 mode bits
        mode15: u2 = 0,
        ///CNF15 [30:31]
        ///Port n.15 configuration
        ///bits
        cnf15: u2 = 1,
    };
    ///Port configuration register high
    ///(GPIOn_CRL)
    pub const crh = Register(crh_val).init(0x40012000 + 0x4);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR0 [0:0]
        ///Port input data
        idr0: u1 = 0,
        ///IDR1 [1:1]
        ///Port input data
        idr1: u1 = 0,
        ///IDR2 [2:2]
        ///Port input data
        idr2: u1 = 0,
        ///IDR3 [3:3]
        ///Port input data
        idr3: u1 = 0,
        ///IDR4 [4:4]
        ///Port input data
        idr4: u1 = 0,
        ///IDR5 [5:5]
        ///Port input data
        idr5: u1 = 0,
        ///IDR6 [6:6]
        ///Port input data
        idr6: u1 = 0,
        ///IDR7 [7:7]
        ///Port input data
        idr7: u1 = 0,
        ///IDR8 [8:8]
        ///Port input data
        idr8: u1 = 0,
        ///IDR9 [9:9]
        ///Port input data
        idr9: u1 = 0,
        ///IDR10 [10:10]
        ///Port input data
        idr10: u1 = 0,
        ///IDR11 [11:11]
        ///Port input data
        idr11: u1 = 0,
        ///IDR12 [12:12]
        ///Port input data
        idr12: u1 = 0,
        ///IDR13 [13:13]
        ///Port input data
        idr13: u1 = 0,
        ///IDR14 [14:14]
        ///Port input data
        idr14: u1 = 0,
        ///IDR15 [15:15]
        ///Port input data
        idr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port input data register
    ///(GPIOn_IDR)
    pub const idr = RegisterRW(idr_val, void).init(0x40012000 + 0x8);

    //////////////////////////
    ///ODR
    const odr_val = packed struct {
        ///ODR0 [0:0]
        ///Port output data
        odr0: u1 = 0,
        ///ODR1 [1:1]
        ///Port output data
        odr1: u1 = 0,
        ///ODR2 [2:2]
        ///Port output data
        odr2: u1 = 0,
        ///ODR3 [3:3]
        ///Port output data
        odr3: u1 = 0,
        ///ODR4 [4:4]
        ///Port output data
        odr4: u1 = 0,
        ///ODR5 [5:5]
        ///Port output data
        odr5: u1 = 0,
        ///ODR6 [6:6]
        ///Port output data
        odr6: u1 = 0,
        ///ODR7 [7:7]
        ///Port output data
        odr7: u1 = 0,
        ///ODR8 [8:8]
        ///Port output data
        odr8: u1 = 0,
        ///ODR9 [9:9]
        ///Port output data
        odr9: u1 = 0,
        ///ODR10 [10:10]
        ///Port output data
        odr10: u1 = 0,
        ///ODR11 [11:11]
        ///Port output data
        odr11: u1 = 0,
        ///ODR12 [12:12]
        ///Port output data
        odr12: u1 = 0,
        ///ODR13 [13:13]
        ///Port output data
        odr13: u1 = 0,
        ///ODR14 [14:14]
        ///Port output data
        odr14: u1 = 0,
        ///ODR15 [15:15]
        ///Port output data
        odr15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port output data register
    ///(GPIOn_ODR)
    pub const odr = Register(odr_val).init(0x40012000 + 0xC);

    //////////////////////////
    ///BSRR
    const bsrr_val = packed struct {
        ///BS0 [0:0]
        ///Set bit 0
        bs0: u1 = 0,
        ///BS1 [1:1]
        ///Set bit 1
        bs1: u1 = 0,
        ///BS2 [2:2]
        ///Set bit 1
        bs2: u1 = 0,
        ///BS3 [3:3]
        ///Set bit 3
        bs3: u1 = 0,
        ///BS4 [4:4]
        ///Set bit 4
        bs4: u1 = 0,
        ///BS5 [5:5]
        ///Set bit 5
        bs5: u1 = 0,
        ///BS6 [6:6]
        ///Set bit 6
        bs6: u1 = 0,
        ///BS7 [7:7]
        ///Set bit 7
        bs7: u1 = 0,
        ///BS8 [8:8]
        ///Set bit 8
        bs8: u1 = 0,
        ///BS9 [9:9]
        ///Set bit 9
        bs9: u1 = 0,
        ///BS10 [10:10]
        ///Set bit 10
        bs10: u1 = 0,
        ///BS11 [11:11]
        ///Set bit 11
        bs11: u1 = 0,
        ///BS12 [12:12]
        ///Set bit 12
        bs12: u1 = 0,
        ///BS13 [13:13]
        ///Set bit 13
        bs13: u1 = 0,
        ///BS14 [14:14]
        ///Set bit 14
        bs14: u1 = 0,
        ///BS15 [15:15]
        ///Set bit 15
        bs15: u1 = 0,
        ///BR0 [16:16]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [17:17]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [18:18]
        ///Reset bit 2
        br2: u1 = 0,
        ///BR3 [19:19]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [20:20]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [21:21]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [22:22]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [23:23]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [24:24]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [25:25]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [26:26]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [27:27]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [28:28]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [29:29]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [30:30]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [31:31]
        ///Reset bit 15
        br15: u1 = 0,
    };
    ///Port bit set/reset register
    ///(GPIOn_BSRR)
    pub const bsrr = RegisterRW(void, bsrr_val).init(0x40012000 + 0x10);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///BR0 [0:0]
        ///Reset bit 0
        br0: u1 = 0,
        ///BR1 [1:1]
        ///Reset bit 1
        br1: u1 = 0,
        ///BR2 [2:2]
        ///Reset bit 1
        br2: u1 = 0,
        ///BR3 [3:3]
        ///Reset bit 3
        br3: u1 = 0,
        ///BR4 [4:4]
        ///Reset bit 4
        br4: u1 = 0,
        ///BR5 [5:5]
        ///Reset bit 5
        br5: u1 = 0,
        ///BR6 [6:6]
        ///Reset bit 6
        br6: u1 = 0,
        ///BR7 [7:7]
        ///Reset bit 7
        br7: u1 = 0,
        ///BR8 [8:8]
        ///Reset bit 8
        br8: u1 = 0,
        ///BR9 [9:9]
        ///Reset bit 9
        br9: u1 = 0,
        ///BR10 [10:10]
        ///Reset bit 10
        br10: u1 = 0,
        ///BR11 [11:11]
        ///Reset bit 11
        br11: u1 = 0,
        ///BR12 [12:12]
        ///Reset bit 12
        br12: u1 = 0,
        ///BR13 [13:13]
        ///Reset bit 13
        br13: u1 = 0,
        ///BR14 [14:14]
        ///Reset bit 14
        br14: u1 = 0,
        ///BR15 [15:15]
        ///Reset bit 15
        br15: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Port bit reset register
    ///(GPIOn_BRR)
    pub const brr = RegisterRW(void, brr_val).init(0x40012000 + 0x14);

    //////////////////////////
    ///LCKR
    const lckr_val = packed struct {
        ///LCK0 [0:0]
        ///Port A Lock bit 0
        lck0: u1 = 0,
        ///LCK1 [1:1]
        ///Port A Lock bit 1
        lck1: u1 = 0,
        ///LCK2 [2:2]
        ///Port A Lock bit 2
        lck2: u1 = 0,
        ///LCK3 [3:3]
        ///Port A Lock bit 3
        lck3: u1 = 0,
        ///LCK4 [4:4]
        ///Port A Lock bit 4
        lck4: u1 = 0,
        ///LCK5 [5:5]
        ///Port A Lock bit 5
        lck5: u1 = 0,
        ///LCK6 [6:6]
        ///Port A Lock bit 6
        lck6: u1 = 0,
        ///LCK7 [7:7]
        ///Port A Lock bit 7
        lck7: u1 = 0,
        ///LCK8 [8:8]
        ///Port A Lock bit 8
        lck8: u1 = 0,
        ///LCK9 [9:9]
        ///Port A Lock bit 9
        lck9: u1 = 0,
        ///LCK10 [10:10]
        ///Port A Lock bit 10
        lck10: u1 = 0,
        ///LCK11 [11:11]
        ///Port A Lock bit 11
        lck11: u1 = 0,
        ///LCK12 [12:12]
        ///Port A Lock bit 12
        lck12: u1 = 0,
        ///LCK13 [13:13]
        ///Port A Lock bit 13
        lck13: u1 = 0,
        ///LCK14 [14:14]
        ///Port A Lock bit 14
        lck14: u1 = 0,
        ///LCK15 [15:15]
        ///Port A Lock bit 15
        lck15: u1 = 0,
        ///LCKK [16:16]
        ///Lock key
        lckk: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Port configuration lock
    ///register
    pub const lckr = Register(lckr_val).init(0x40012000 + 0x18);
};

///Alternate function I/O
pub const afio = struct {

    //////////////////////////
    ///EVCR
    const evcr_val = packed struct {
        ///PIN [0:3]
        ///Pin selection
        pin: u4 = 0,
        ///PORT [4:6]
        ///Port selection
        port: u3 = 0,
        ///EVOE [7:7]
        ///Event Output Enable
        evoe: u1 = 0,
        _unused8: u24 = 0,
    };
    ///Event Control Register
    ///(AFIO_EVCR)
    pub const evcr = Register(evcr_val).init(0x40010000 + 0x0);

    //////////////////////////
    ///MAPR
    const mapr_val = packed struct {
        ///SPI1_REMAP [0:0]
        ///SPI1 remapping
        spi1_remap: u1 = 0,
        ///I2C1_REMAP [1:1]
        ///I2C1 remapping
        i2c1_remap: u1 = 0,
        ///USART1_REMAP [2:2]
        ///USART1 remapping
        usart1_remap: u1 = 0,
        ///USART2_REMAP [3:3]
        ///USART2 remapping
        usart2_remap: u1 = 0,
        ///USART3_REMAP [4:5]
        ///USART3 remapping
        usart3_remap: u2 = 0,
        ///TIM1_REMAP [6:7]
        ///TIM1 remapping
        tim1_remap: u2 = 0,
        ///TIM2_REMAP [8:9]
        ///TIM2 remapping
        tim2_remap: u2 = 0,
        ///TIM3_REMAP [10:11]
        ///TIM3 remapping
        tim3_remap: u2 = 0,
        ///TIM4_REMAP [12:12]
        ///TIM4 remapping
        tim4_remap: u1 = 0,
        ///CAN_REMAP [13:14]
        ///CAN1 remapping
        can_remap: u2 = 0,
        ///PD01_REMAP [15:15]
        ///Port D0/Port D1 mapping on
        ///OSCIN/OSCOUT
        pd01_remap: u1 = 0,
        ///TIM5CH4_IREMAP [16:16]
        ///Set and cleared by
        ///software
        tim5ch4_iremap: u1 = 0,
        ///ADC1_ETRGINJ_REMAP [17:17]
        ///ADC 1 External trigger injected
        ///conversion remapping
        adc1_etrginj_remap: u1 = 0,
        ///ADC1_ETRGREG_REMAP [18:18]
        ///ADC 1 external trigger regular
        ///conversion remapping
        adc1_etrgreg_remap: u1 = 0,
        ///ADC2_ETRGINJ_REMAP [19:19]
        ///ADC 2 external trigger injected
        ///conversion remapping
        adc2_etrginj_remap: u1 = 0,
        ///ADC2_ETRGREG_REMAP [20:20]
        ///ADC 2 external trigger regular
        ///conversion remapping
        adc2_etrgreg_remap: u1 = 0,
        _unused21: u3 = 0,
        ///SWJ_CFG [24:26]
        ///Serial wire JTAG
        ///configuration
        swj_cfg: u3 = 0,
        _unused27: u5 = 0,
    };
    ///AF remap and debug I/O configuration
    ///register (AFIO_MAPR)
    pub const mapr = Register(mapr_val).init(0x40010000 + 0x4);

    //////////////////////////
    ///EXTICR1
    const exticr1_val = packed struct {
        ///EXTI0 [0:3]
        ///EXTI0 configuration
        exti0: u4 = 0,
        ///EXTI1 [4:7]
        ///EXTI1 configuration
        exti1: u4 = 0,
        ///EXTI2 [8:11]
        ///EXTI2 configuration
        exti2: u4 = 0,
        ///EXTI3 [12:15]
        ///EXTI3 configuration
        exti3: u4 = 0,
        _unused16: u16 = 0,
    };
    ///External interrupt configuration register 1
    ///(AFIO_EXTICR1)
    pub const exticr1 = Register(exticr1_val).init(0x40010000 + 0x8);

    //////////////////////////
    ///EXTICR2
    const exticr2_val = packed struct {
        ///EXTI4 [0:3]
        ///EXTI4 configuration
        exti4: u4 = 0,
        ///EXTI5 [4:7]
        ///EXTI5 configuration
        exti5: u4 = 0,
        ///EXTI6 [8:11]
        ///EXTI6 configuration
        exti6: u4 = 0,
        ///EXTI7 [12:15]
        ///EXTI7 configuration
        exti7: u4 = 0,
        _unused16: u16 = 0,
    };
    ///External interrupt configuration register 2
    ///(AFIO_EXTICR2)
    pub const exticr2 = Register(exticr2_val).init(0x40010000 + 0xC);

    //////////////////////////
    ///EXTICR3
    const exticr3_val = packed struct {
        ///EXTI8 [0:3]
        ///EXTI8 configuration
        exti8: u4 = 0,
        ///EXTI9 [4:7]
        ///EXTI9 configuration
        exti9: u4 = 0,
        ///EXTI10 [8:11]
        ///EXTI10 configuration
        exti10: u4 = 0,
        ///EXTI11 [12:15]
        ///EXTI11 configuration
        exti11: u4 = 0,
        _unused16: u16 = 0,
    };
    ///External interrupt configuration register 3
    ///(AFIO_EXTICR3)
    pub const exticr3 = Register(exticr3_val).init(0x40010000 + 0x10);

    //////////////////////////
    ///EXTICR4
    const exticr4_val = packed struct {
        ///EXTI12 [0:3]
        ///EXTI12 configuration
        exti12: u4 = 0,
        ///EXTI13 [4:7]
        ///EXTI13 configuration
        exti13: u4 = 0,
        ///EXTI14 [8:11]
        ///EXTI14 configuration
        exti14: u4 = 0,
        ///EXTI15 [12:15]
        ///EXTI15 configuration
        exti15: u4 = 0,
        _unused16: u16 = 0,
    };
    ///External interrupt configuration register 4
    ///(AFIO_EXTICR4)
    pub const exticr4 = Register(exticr4_val).init(0x40010000 + 0x14);

    //////////////////////////
    ///MAPR2
    const mapr2_val = packed struct {
        _unused0: u5 = 0,
        ///TIM9_REMAP [5:5]
        ///TIM9 remapping
        tim9_remap: u1 = 0,
        ///TIM10_REMAP [6:6]
        ///TIM10 remapping
        tim10_remap: u1 = 0,
        ///TIM11_REMAP [7:7]
        ///TIM11 remapping
        tim11_remap: u1 = 0,
        ///TIM13_REMAP [8:8]
        ///TIM13 remapping
        tim13_remap: u1 = 0,
        ///TIM14_REMAP [9:9]
        ///TIM14 remapping
        tim14_remap: u1 = 0,
        ///FSMC_NADV [10:10]
        ///NADV connect/disconnect
        fsmc_nadv: u1 = 0,
        _unused11: u21 = 0,
    };
    ///AF remap and debug I/O configuration
    ///register
    pub const mapr2 = Register(mapr2_val).init(0x40010000 + 0x1C);
};

///EXTI
pub const exti = struct {

    //////////////////////////
    ///IMR
    const imr_val = packed struct {
        ///MR0 [0:0]
        ///Interrupt Mask on line 0
        mr0: u1 = 0,
        ///MR1 [1:1]
        ///Interrupt Mask on line 1
        mr1: u1 = 0,
        ///MR2 [2:2]
        ///Interrupt Mask on line 2
        mr2: u1 = 0,
        ///MR3 [3:3]
        ///Interrupt Mask on line 3
        mr3: u1 = 0,
        ///MR4 [4:4]
        ///Interrupt Mask on line 4
        mr4: u1 = 0,
        ///MR5 [5:5]
        ///Interrupt Mask on line 5
        mr5: u1 = 0,
        ///MR6 [6:6]
        ///Interrupt Mask on line 6
        mr6: u1 = 0,
        ///MR7 [7:7]
        ///Interrupt Mask on line 7
        mr7: u1 = 0,
        ///MR8 [8:8]
        ///Interrupt Mask on line 8
        mr8: u1 = 0,
        ///MR9 [9:9]
        ///Interrupt Mask on line 9
        mr9: u1 = 0,
        ///MR10 [10:10]
        ///Interrupt Mask on line 10
        mr10: u1 = 0,
        ///MR11 [11:11]
        ///Interrupt Mask on line 11
        mr11: u1 = 0,
        ///MR12 [12:12]
        ///Interrupt Mask on line 12
        mr12: u1 = 0,
        ///MR13 [13:13]
        ///Interrupt Mask on line 13
        mr13: u1 = 0,
        ///MR14 [14:14]
        ///Interrupt Mask on line 14
        mr14: u1 = 0,
        ///MR15 [15:15]
        ///Interrupt Mask on line 15
        mr15: u1 = 0,
        ///MR16 [16:16]
        ///Interrupt Mask on line 16
        mr16: u1 = 0,
        ///MR17 [17:17]
        ///Interrupt Mask on line 17
        mr17: u1 = 0,
        ///MR18 [18:18]
        ///Interrupt Mask on line 18
        mr18: u1 = 0,
        _unused19: u13 = 0,
    };
    ///Interrupt mask register
    ///(EXTI_IMR)
    pub const imr = Register(imr_val).init(0x40010400 + 0x0);

    //////////////////////////
    ///EMR
    const emr_val = packed struct {
        ///MR0 [0:0]
        ///Event Mask on line 0
        mr0: u1 = 0,
        ///MR1 [1:1]
        ///Event Mask on line 1
        mr1: u1 = 0,
        ///MR2 [2:2]
        ///Event Mask on line 2
        mr2: u1 = 0,
        ///MR3 [3:3]
        ///Event Mask on line 3
        mr3: u1 = 0,
        ///MR4 [4:4]
        ///Event Mask on line 4
        mr4: u1 = 0,
        ///MR5 [5:5]
        ///Event Mask on line 5
        mr5: u1 = 0,
        ///MR6 [6:6]
        ///Event Mask on line 6
        mr6: u1 = 0,
        ///MR7 [7:7]
        ///Event Mask on line 7
        mr7: u1 = 0,
        ///MR8 [8:8]
        ///Event Mask on line 8
        mr8: u1 = 0,
        ///MR9 [9:9]
        ///Event Mask on line 9
        mr9: u1 = 0,
        ///MR10 [10:10]
        ///Event Mask on line 10
        mr10: u1 = 0,
        ///MR11 [11:11]
        ///Event Mask on line 11
        mr11: u1 = 0,
        ///MR12 [12:12]
        ///Event Mask on line 12
        mr12: u1 = 0,
        ///MR13 [13:13]
        ///Event Mask on line 13
        mr13: u1 = 0,
        ///MR14 [14:14]
        ///Event Mask on line 14
        mr14: u1 = 0,
        ///MR15 [15:15]
        ///Event Mask on line 15
        mr15: u1 = 0,
        ///MR16 [16:16]
        ///Event Mask on line 16
        mr16: u1 = 0,
        ///MR17 [17:17]
        ///Event Mask on line 17
        mr17: u1 = 0,
        ///MR18 [18:18]
        ///Event Mask on line 18
        mr18: u1 = 0,
        _unused19: u13 = 0,
    };
    ///Event mask register (EXTI_EMR)
    pub const emr = Register(emr_val).init(0x40010400 + 0x4);

    //////////////////////////
    ///RTSR
    const rtsr_val = packed struct {
        ///TR0 [0:0]
        ///Rising trigger event configuration of
        ///line 0
        tr0: u1 = 0,
        ///TR1 [1:1]
        ///Rising trigger event configuration of
        ///line 1
        tr1: u1 = 0,
        ///TR2 [2:2]
        ///Rising trigger event configuration of
        ///line 2
        tr2: u1 = 0,
        ///TR3 [3:3]
        ///Rising trigger event configuration of
        ///line 3
        tr3: u1 = 0,
        ///TR4 [4:4]
        ///Rising trigger event configuration of
        ///line 4
        tr4: u1 = 0,
        ///TR5 [5:5]
        ///Rising trigger event configuration of
        ///line 5
        tr5: u1 = 0,
        ///TR6 [6:6]
        ///Rising trigger event configuration of
        ///line 6
        tr6: u1 = 0,
        ///TR7 [7:7]
        ///Rising trigger event configuration of
        ///line 7
        tr7: u1 = 0,
        ///TR8 [8:8]
        ///Rising trigger event configuration of
        ///line 8
        tr8: u1 = 0,
        ///TR9 [9:9]
        ///Rising trigger event configuration of
        ///line 9
        tr9: u1 = 0,
        ///TR10 [10:10]
        ///Rising trigger event configuration of
        ///line 10
        tr10: u1 = 0,
        ///TR11 [11:11]
        ///Rising trigger event configuration of
        ///line 11
        tr11: u1 = 0,
        ///TR12 [12:12]
        ///Rising trigger event configuration of
        ///line 12
        tr12: u1 = 0,
        ///TR13 [13:13]
        ///Rising trigger event configuration of
        ///line 13
        tr13: u1 = 0,
        ///TR14 [14:14]
        ///Rising trigger event configuration of
        ///line 14
        tr14: u1 = 0,
        ///TR15 [15:15]
        ///Rising trigger event configuration of
        ///line 15
        tr15: u1 = 0,
        ///TR16 [16:16]
        ///Rising trigger event configuration of
        ///line 16
        tr16: u1 = 0,
        ///TR17 [17:17]
        ///Rising trigger event configuration of
        ///line 17
        tr17: u1 = 0,
        ///TR18 [18:18]
        ///Rising trigger event configuration of
        ///line 18
        tr18: u1 = 0,
        _unused19: u13 = 0,
    };
    ///Rising Trigger selection register
    ///(EXTI_RTSR)
    pub const rtsr = Register(rtsr_val).init(0x40010400 + 0x8);

    //////////////////////////
    ///FTSR
    const ftsr_val = packed struct {
        ///TR0 [0:0]
        ///Falling trigger event configuration of
        ///line 0
        tr0: u1 = 0,
        ///TR1 [1:1]
        ///Falling trigger event configuration of
        ///line 1
        tr1: u1 = 0,
        ///TR2 [2:2]
        ///Falling trigger event configuration of
        ///line 2
        tr2: u1 = 0,
        ///TR3 [3:3]
        ///Falling trigger event configuration of
        ///line 3
        tr3: u1 = 0,
        ///TR4 [4:4]
        ///Falling trigger event configuration of
        ///line 4
        tr4: u1 = 0,
        ///TR5 [5:5]
        ///Falling trigger event configuration of
        ///line 5
        tr5: u1 = 0,
        ///TR6 [6:6]
        ///Falling trigger event configuration of
        ///line 6
        tr6: u1 = 0,
        ///TR7 [7:7]
        ///Falling trigger event configuration of
        ///line 7
        tr7: u1 = 0,
        ///TR8 [8:8]
        ///Falling trigger event configuration of
        ///line 8
        tr8: u1 = 0,
        ///TR9 [9:9]
        ///Falling trigger event configuration of
        ///line 9
        tr9: u1 = 0,
        ///TR10 [10:10]
        ///Falling trigger event configuration of
        ///line 10
        tr10: u1 = 0,
        ///TR11 [11:11]
        ///Falling trigger event configuration of
        ///line 11
        tr11: u1 = 0,
        ///TR12 [12:12]
        ///Falling trigger event configuration of
        ///line 12
        tr12: u1 = 0,
        ///TR13 [13:13]
        ///Falling trigger event configuration of
        ///line 13
        tr13: u1 = 0,
        ///TR14 [14:14]
        ///Falling trigger event configuration of
        ///line 14
        tr14: u1 = 0,
        ///TR15 [15:15]
        ///Falling trigger event configuration of
        ///line 15
        tr15: u1 = 0,
        ///TR16 [16:16]
        ///Falling trigger event configuration of
        ///line 16
        tr16: u1 = 0,
        ///TR17 [17:17]
        ///Falling trigger event configuration of
        ///line 17
        tr17: u1 = 0,
        ///TR18 [18:18]
        ///Falling trigger event configuration of
        ///line 18
        tr18: u1 = 0,
        _unused19: u13 = 0,
    };
    ///Falling Trigger selection register
    ///(EXTI_FTSR)
    pub const ftsr = Register(ftsr_val).init(0x40010400 + 0xC);

    //////////////////////////
    ///SWIER
    const swier_val = packed struct {
        ///SWIER0 [0:0]
        ///Software Interrupt on line
        ///0
        swier0: u1 = 0,
        ///SWIER1 [1:1]
        ///Software Interrupt on line
        ///1
        swier1: u1 = 0,
        ///SWIER2 [2:2]
        ///Software Interrupt on line
        ///2
        swier2: u1 = 0,
        ///SWIER3 [3:3]
        ///Software Interrupt on line
        ///3
        swier3: u1 = 0,
        ///SWIER4 [4:4]
        ///Software Interrupt on line
        ///4
        swier4: u1 = 0,
        ///SWIER5 [5:5]
        ///Software Interrupt on line
        ///5
        swier5: u1 = 0,
        ///SWIER6 [6:6]
        ///Software Interrupt on line
        ///6
        swier6: u1 = 0,
        ///SWIER7 [7:7]
        ///Software Interrupt on line
        ///7
        swier7: u1 = 0,
        ///SWIER8 [8:8]
        ///Software Interrupt on line
        ///8
        swier8: u1 = 0,
        ///SWIER9 [9:9]
        ///Software Interrupt on line
        ///9
        swier9: u1 = 0,
        ///SWIER10 [10:10]
        ///Software Interrupt on line
        ///10
        swier10: u1 = 0,
        ///SWIER11 [11:11]
        ///Software Interrupt on line
        ///11
        swier11: u1 = 0,
        ///SWIER12 [12:12]
        ///Software Interrupt on line
        ///12
        swier12: u1 = 0,
        ///SWIER13 [13:13]
        ///Software Interrupt on line
        ///13
        swier13: u1 = 0,
        ///SWIER14 [14:14]
        ///Software Interrupt on line
        ///14
        swier14: u1 = 0,
        ///SWIER15 [15:15]
        ///Software Interrupt on line
        ///15
        swier15: u1 = 0,
        ///SWIER16 [16:16]
        ///Software Interrupt on line
        ///16
        swier16: u1 = 0,
        ///SWIER17 [17:17]
        ///Software Interrupt on line
        ///17
        swier17: u1 = 0,
        ///SWIER18 [18:18]
        ///Software Interrupt on line
        ///18
        swier18: u1 = 0,
        _unused19: u13 = 0,
    };
    ///Software interrupt event register
    ///(EXTI_SWIER)
    pub const swier = Register(swier_val).init(0x40010400 + 0x10);

    //////////////////////////
    ///PR
    const pr_val = packed struct {
        ///PR0 [0:0]
        ///Pending bit 0
        pr0: u1 = 0,
        ///PR1 [1:1]
        ///Pending bit 1
        pr1: u1 = 0,
        ///PR2 [2:2]
        ///Pending bit 2
        pr2: u1 = 0,
        ///PR3 [3:3]
        ///Pending bit 3
        pr3: u1 = 0,
        ///PR4 [4:4]
        ///Pending bit 4
        pr4: u1 = 0,
        ///PR5 [5:5]
        ///Pending bit 5
        pr5: u1 = 0,
        ///PR6 [6:6]
        ///Pending bit 6
        pr6: u1 = 0,
        ///PR7 [7:7]
        ///Pending bit 7
        pr7: u1 = 0,
        ///PR8 [8:8]
        ///Pending bit 8
        pr8: u1 = 0,
        ///PR9 [9:9]
        ///Pending bit 9
        pr9: u1 = 0,
        ///PR10 [10:10]
        ///Pending bit 10
        pr10: u1 = 0,
        ///PR11 [11:11]
        ///Pending bit 11
        pr11: u1 = 0,
        ///PR12 [12:12]
        ///Pending bit 12
        pr12: u1 = 0,
        ///PR13 [13:13]
        ///Pending bit 13
        pr13: u1 = 0,
        ///PR14 [14:14]
        ///Pending bit 14
        pr14: u1 = 0,
        ///PR15 [15:15]
        ///Pending bit 15
        pr15: u1 = 0,
        ///PR16 [16:16]
        ///Pending bit 16
        pr16: u1 = 0,
        ///PR17 [17:17]
        ///Pending bit 17
        pr17: u1 = 0,
        ///PR18 [18:18]
        ///Pending bit 18
        pr18: u1 = 0,
        _unused19: u13 = 0,
    };
    ///Pending register (EXTI_PR)
    pub const pr = Register(pr_val).init(0x40010400 + 0x14);
};

///DMA controller
pub const dma1 = struct {

    //////////////////////////
    ///ISR
    const isr_val = packed struct {
        ///GIF1 [0:0]
        ///Channel 1 Global interrupt
        ///flag
        gif1: u1 = 0,
        ///TCIF1 [1:1]
        ///Channel 1 Transfer Complete
        ///flag
        tcif1: u1 = 0,
        ///HTIF1 [2:2]
        ///Channel 1 Half Transfer Complete
        ///flag
        htif1: u1 = 0,
        ///TEIF1 [3:3]
        ///Channel 1 Transfer Error
        ///flag
        teif1: u1 = 0,
        ///GIF2 [4:4]
        ///Channel 2 Global interrupt
        ///flag
        gif2: u1 = 0,
        ///TCIF2 [5:5]
        ///Channel 2 Transfer Complete
        ///flag
        tcif2: u1 = 0,
        ///HTIF2 [6:6]
        ///Channel 2 Half Transfer Complete
        ///flag
        htif2: u1 = 0,
        ///TEIF2 [7:7]
        ///Channel 2 Transfer Error
        ///flag
        teif2: u1 = 0,
        ///GIF3 [8:8]
        ///Channel 3 Global interrupt
        ///flag
        gif3: u1 = 0,
        ///TCIF3 [9:9]
        ///Channel 3 Transfer Complete
        ///flag
        tcif3: u1 = 0,
        ///HTIF3 [10:10]
        ///Channel 3 Half Transfer Complete
        ///flag
        htif3: u1 = 0,
        ///TEIF3 [11:11]
        ///Channel 3 Transfer Error
        ///flag
        teif3: u1 = 0,
        ///GIF4 [12:12]
        ///Channel 4 Global interrupt
        ///flag
        gif4: u1 = 0,
        ///TCIF4 [13:13]
        ///Channel 4 Transfer Complete
        ///flag
        tcif4: u1 = 0,
        ///HTIF4 [14:14]
        ///Channel 4 Half Transfer Complete
        ///flag
        htif4: u1 = 0,
        ///TEIF4 [15:15]
        ///Channel 4 Transfer Error
        ///flag
        teif4: u1 = 0,
        ///GIF5 [16:16]
        ///Channel 5 Global interrupt
        ///flag
        gif5: u1 = 0,
        ///TCIF5 [17:17]
        ///Channel 5 Transfer Complete
        ///flag
        tcif5: u1 = 0,
        ///HTIF5 [18:18]
        ///Channel 5 Half Transfer Complete
        ///flag
        htif5: u1 = 0,
        ///TEIF5 [19:19]
        ///Channel 5 Transfer Error
        ///flag
        teif5: u1 = 0,
        ///GIF6 [20:20]
        ///Channel 6 Global interrupt
        ///flag
        gif6: u1 = 0,
        ///TCIF6 [21:21]
        ///Channel 6 Transfer Complete
        ///flag
        tcif6: u1 = 0,
        ///HTIF6 [22:22]
        ///Channel 6 Half Transfer Complete
        ///flag
        htif6: u1 = 0,
        ///TEIF6 [23:23]
        ///Channel 6 Transfer Error
        ///flag
        teif6: u1 = 0,
        ///GIF7 [24:24]
        ///Channel 7 Global interrupt
        ///flag
        gif7: u1 = 0,
        ///TCIF7 [25:25]
        ///Channel 7 Transfer Complete
        ///flag
        tcif7: u1 = 0,
        ///HTIF7 [26:26]
        ///Channel 7 Half Transfer Complete
        ///flag
        htif7: u1 = 0,
        ///TEIF7 [27:27]
        ///Channel 7 Transfer Error
        ///flag
        teif7: u1 = 0,
        _unused28: u4 = 0,
    };
    ///DMA interrupt status register
    ///(DMA_ISR)
    pub const isr = RegisterRW(isr_val, void).init(0x40020000 + 0x0);

    //////////////////////////
    ///IFCR
    const ifcr_val = packed struct {
        ///CGIF1 [0:0]
        ///Channel 1 Global interrupt
        ///clear
        cgif1: u1 = 0,
        ///CTCIF1 [1:1]
        ///Channel 1 Transfer Complete
        ///clear
        ctcif1: u1 = 0,
        ///CHTIF1 [2:2]
        ///Channel 1 Half Transfer
        ///clear
        chtif1: u1 = 0,
        ///CTEIF1 [3:3]
        ///Channel 1 Transfer Error
        ///clear
        cteif1: u1 = 0,
        ///CGIF2 [4:4]
        ///Channel 2 Global interrupt
        ///clear
        cgif2: u1 = 0,
        ///CTCIF2 [5:5]
        ///Channel 2 Transfer Complete
        ///clear
        ctcif2: u1 = 0,
        ///CHTIF2 [6:6]
        ///Channel 2 Half Transfer
        ///clear
        chtif2: u1 = 0,
        ///CTEIF2 [7:7]
        ///Channel 2 Transfer Error
        ///clear
        cteif2: u1 = 0,
        ///CGIF3 [8:8]
        ///Channel 3 Global interrupt
        ///clear
        cgif3: u1 = 0,
        ///CTCIF3 [9:9]
        ///Channel 3 Transfer Complete
        ///clear
        ctcif3: u1 = 0,
        ///CHTIF3 [10:10]
        ///Channel 3 Half Transfer
        ///clear
        chtif3: u1 = 0,
        ///CTEIF3 [11:11]
        ///Channel 3 Transfer Error
        ///clear
        cteif3: u1 = 0,
        ///CGIF4 [12:12]
        ///Channel 4 Global interrupt
        ///clear
        cgif4: u1 = 0,
        ///CTCIF4 [13:13]
        ///Channel 4 Transfer Complete
        ///clear
        ctcif4: u1 = 0,
        ///CHTIF4 [14:14]
        ///Channel 4 Half Transfer
        ///clear
        chtif4: u1 = 0,
        ///CTEIF4 [15:15]
        ///Channel 4 Transfer Error
        ///clear
        cteif4: u1 = 0,
        ///CGIF5 [16:16]
        ///Channel 5 Global interrupt
        ///clear
        cgif5: u1 = 0,
        ///CTCIF5 [17:17]
        ///Channel 5 Transfer Complete
        ///clear
        ctcif5: u1 = 0,
        ///CHTIF5 [18:18]
        ///Channel 5 Half Transfer
        ///clear
        chtif5: u1 = 0,
        ///CTEIF5 [19:19]
        ///Channel 5 Transfer Error
        ///clear
        cteif5: u1 = 0,
        ///CGIF6 [20:20]
        ///Channel 6 Global interrupt
        ///clear
        cgif6: u1 = 0,
        ///CTCIF6 [21:21]
        ///Channel 6 Transfer Complete
        ///clear
        ctcif6: u1 = 0,
        ///CHTIF6 [22:22]
        ///Channel 6 Half Transfer
        ///clear
        chtif6: u1 = 0,
        ///CTEIF6 [23:23]
        ///Channel 6 Transfer Error
        ///clear
        cteif6: u1 = 0,
        ///CGIF7 [24:24]
        ///Channel 7 Global interrupt
        ///clear
        cgif7: u1 = 0,
        ///CTCIF7 [25:25]
        ///Channel 7 Transfer Complete
        ///clear
        ctcif7: u1 = 0,
        ///CHTIF7 [26:26]
        ///Channel 7 Half Transfer
        ///clear
        chtif7: u1 = 0,
        ///CTEIF7 [27:27]
        ///Channel 7 Transfer Error
        ///clear
        cteif7: u1 = 0,
        _unused28: u4 = 0,
    };
    ///DMA interrupt flag clear register
    ///(DMA_IFCR)
    pub const ifcr = RegisterRW(void, ifcr_val).init(0x40020000 + 0x4);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr1 = Register(ccr1_val).init(0x40020000 + 0x8);

    //////////////////////////
    ///CNDTR1
    const cndtr1_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 1 number of data
    ///register
    pub const cndtr1 = Register(cndtr1_val).init(0x40020000 + 0xC);

    //////////////////////////
    ///CPAR1
    const cpar1_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 1 peripheral address
    ///register
    pub const cpar1 = Register(cpar1_val).init(0x40020000 + 0x10);

    //////////////////////////
    ///CMAR1
    const cmar1_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 1 memory address
    ///register
    pub const cmar1 = Register(cmar1_val).init(0x40020000 + 0x14);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr2 = Register(ccr2_val).init(0x40020000 + 0x1C);

    //////////////////////////
    ///CNDTR2
    const cndtr2_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 2 number of data
    ///register
    pub const cndtr2 = Register(cndtr2_val).init(0x40020000 + 0x20);

    //////////////////////////
    ///CPAR2
    const cpar2_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 2 peripheral address
    ///register
    pub const cpar2 = Register(cpar2_val).init(0x40020000 + 0x24);

    //////////////////////////
    ///CMAR2
    const cmar2_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 2 memory address
    ///register
    pub const cmar2 = Register(cmar2_val).init(0x40020000 + 0x28);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr3 = Register(ccr3_val).init(0x40020000 + 0x30);

    //////////////////////////
    ///CNDTR3
    const cndtr3_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 3 number of data
    ///register
    pub const cndtr3 = Register(cndtr3_val).init(0x40020000 + 0x34);

    //////////////////////////
    ///CPAR3
    const cpar3_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 3 peripheral address
    ///register
    pub const cpar3 = Register(cpar3_val).init(0x40020000 + 0x38);

    //////////////////////////
    ///CMAR3
    const cmar3_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 3 memory address
    ///register
    pub const cmar3 = Register(cmar3_val).init(0x40020000 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr4 = Register(ccr4_val).init(0x40020000 + 0x44);

    //////////////////////////
    ///CNDTR4
    const cndtr4_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 4 number of data
    ///register
    pub const cndtr4 = Register(cndtr4_val).init(0x40020000 + 0x48);

    //////////////////////////
    ///CPAR4
    const cpar4_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 4 peripheral address
    ///register
    pub const cpar4 = Register(cpar4_val).init(0x40020000 + 0x4C);

    //////////////////////////
    ///CMAR4
    const cmar4_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 4 memory address
    ///register
    pub const cmar4 = Register(cmar4_val).init(0x40020000 + 0x50);

    //////////////////////////
    ///CCR5
    const ccr5_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr5 = Register(ccr5_val).init(0x40020000 + 0x58);

    //////////////////////////
    ///CNDTR5
    const cndtr5_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 5 number of data
    ///register
    pub const cndtr5 = Register(cndtr5_val).init(0x40020000 + 0x5C);

    //////////////////////////
    ///CPAR5
    const cpar5_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 5 peripheral address
    ///register
    pub const cpar5 = Register(cpar5_val).init(0x40020000 + 0x60);

    //////////////////////////
    ///CMAR5
    const cmar5_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 5 memory address
    ///register
    pub const cmar5 = Register(cmar5_val).init(0x40020000 + 0x64);

    //////////////////////////
    ///CCR6
    const ccr6_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr6 = Register(ccr6_val).init(0x40020000 + 0x6C);

    //////////////////////////
    ///CNDTR6
    const cndtr6_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 6 number of data
    ///register
    pub const cndtr6 = Register(cndtr6_val).init(0x40020000 + 0x70);

    //////////////////////////
    ///CPAR6
    const cpar6_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 6 peripheral address
    ///register
    pub const cpar6 = Register(cpar6_val).init(0x40020000 + 0x74);

    //////////////////////////
    ///CMAR6
    const cmar6_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 6 memory address
    ///register
    pub const cmar6 = Register(cmar6_val).init(0x40020000 + 0x78);

    //////////////////////////
    ///CCR7
    const ccr7_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr7 = Register(ccr7_val).init(0x40020000 + 0x80);

    //////////////////////////
    ///CNDTR7
    const cndtr7_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 7 number of data
    ///register
    pub const cndtr7 = Register(cndtr7_val).init(0x40020000 + 0x84);

    //////////////////////////
    ///CPAR7
    const cpar7_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 7 peripheral address
    ///register
    pub const cpar7 = Register(cpar7_val).init(0x40020000 + 0x88);

    //////////////////////////
    ///CMAR7
    const cmar7_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 7 memory address
    ///register
    pub const cmar7 = Register(cmar7_val).init(0x40020000 + 0x8C);
};

///DMA controller
pub const dma2 = struct {

    //////////////////////////
    ///ISR
    const isr_val = packed struct {
        ///GIF1 [0:0]
        ///Channel 1 Global interrupt
        ///flag
        gif1: u1 = 0,
        ///TCIF1 [1:1]
        ///Channel 1 Transfer Complete
        ///flag
        tcif1: u1 = 0,
        ///HTIF1 [2:2]
        ///Channel 1 Half Transfer Complete
        ///flag
        htif1: u1 = 0,
        ///TEIF1 [3:3]
        ///Channel 1 Transfer Error
        ///flag
        teif1: u1 = 0,
        ///GIF2 [4:4]
        ///Channel 2 Global interrupt
        ///flag
        gif2: u1 = 0,
        ///TCIF2 [5:5]
        ///Channel 2 Transfer Complete
        ///flag
        tcif2: u1 = 0,
        ///HTIF2 [6:6]
        ///Channel 2 Half Transfer Complete
        ///flag
        htif2: u1 = 0,
        ///TEIF2 [7:7]
        ///Channel 2 Transfer Error
        ///flag
        teif2: u1 = 0,
        ///GIF3 [8:8]
        ///Channel 3 Global interrupt
        ///flag
        gif3: u1 = 0,
        ///TCIF3 [9:9]
        ///Channel 3 Transfer Complete
        ///flag
        tcif3: u1 = 0,
        ///HTIF3 [10:10]
        ///Channel 3 Half Transfer Complete
        ///flag
        htif3: u1 = 0,
        ///TEIF3 [11:11]
        ///Channel 3 Transfer Error
        ///flag
        teif3: u1 = 0,
        ///GIF4 [12:12]
        ///Channel 4 Global interrupt
        ///flag
        gif4: u1 = 0,
        ///TCIF4 [13:13]
        ///Channel 4 Transfer Complete
        ///flag
        tcif4: u1 = 0,
        ///HTIF4 [14:14]
        ///Channel 4 Half Transfer Complete
        ///flag
        htif4: u1 = 0,
        ///TEIF4 [15:15]
        ///Channel 4 Transfer Error
        ///flag
        teif4: u1 = 0,
        ///GIF5 [16:16]
        ///Channel 5 Global interrupt
        ///flag
        gif5: u1 = 0,
        ///TCIF5 [17:17]
        ///Channel 5 Transfer Complete
        ///flag
        tcif5: u1 = 0,
        ///HTIF5 [18:18]
        ///Channel 5 Half Transfer Complete
        ///flag
        htif5: u1 = 0,
        ///TEIF5 [19:19]
        ///Channel 5 Transfer Error
        ///flag
        teif5: u1 = 0,
        ///GIF6 [20:20]
        ///Channel 6 Global interrupt
        ///flag
        gif6: u1 = 0,
        ///TCIF6 [21:21]
        ///Channel 6 Transfer Complete
        ///flag
        tcif6: u1 = 0,
        ///HTIF6 [22:22]
        ///Channel 6 Half Transfer Complete
        ///flag
        htif6: u1 = 0,
        ///TEIF6 [23:23]
        ///Channel 6 Transfer Error
        ///flag
        teif6: u1 = 0,
        ///GIF7 [24:24]
        ///Channel 7 Global interrupt
        ///flag
        gif7: u1 = 0,
        ///TCIF7 [25:25]
        ///Channel 7 Transfer Complete
        ///flag
        tcif7: u1 = 0,
        ///HTIF7 [26:26]
        ///Channel 7 Half Transfer Complete
        ///flag
        htif7: u1 = 0,
        ///TEIF7 [27:27]
        ///Channel 7 Transfer Error
        ///flag
        teif7: u1 = 0,
        _unused28: u4 = 0,
    };
    ///DMA interrupt status register
    ///(DMA_ISR)
    pub const isr = RegisterRW(isr_val, void).init(0x40020400 + 0x0);

    //////////////////////////
    ///IFCR
    const ifcr_val = packed struct {
        ///CGIF1 [0:0]
        ///Channel 1 Global interrupt
        ///clear
        cgif1: u1 = 0,
        ///CTCIF1 [1:1]
        ///Channel 1 Transfer Complete
        ///clear
        ctcif1: u1 = 0,
        ///CHTIF1 [2:2]
        ///Channel 1 Half Transfer
        ///clear
        chtif1: u1 = 0,
        ///CTEIF1 [3:3]
        ///Channel 1 Transfer Error
        ///clear
        cteif1: u1 = 0,
        ///CGIF2 [4:4]
        ///Channel 2 Global interrupt
        ///clear
        cgif2: u1 = 0,
        ///CTCIF2 [5:5]
        ///Channel 2 Transfer Complete
        ///clear
        ctcif2: u1 = 0,
        ///CHTIF2 [6:6]
        ///Channel 2 Half Transfer
        ///clear
        chtif2: u1 = 0,
        ///CTEIF2 [7:7]
        ///Channel 2 Transfer Error
        ///clear
        cteif2: u1 = 0,
        ///CGIF3 [8:8]
        ///Channel 3 Global interrupt
        ///clear
        cgif3: u1 = 0,
        ///CTCIF3 [9:9]
        ///Channel 3 Transfer Complete
        ///clear
        ctcif3: u1 = 0,
        ///CHTIF3 [10:10]
        ///Channel 3 Half Transfer
        ///clear
        chtif3: u1 = 0,
        ///CTEIF3 [11:11]
        ///Channel 3 Transfer Error
        ///clear
        cteif3: u1 = 0,
        ///CGIF4 [12:12]
        ///Channel 4 Global interrupt
        ///clear
        cgif4: u1 = 0,
        ///CTCIF4 [13:13]
        ///Channel 4 Transfer Complete
        ///clear
        ctcif4: u1 = 0,
        ///CHTIF4 [14:14]
        ///Channel 4 Half Transfer
        ///clear
        chtif4: u1 = 0,
        ///CTEIF4 [15:15]
        ///Channel 4 Transfer Error
        ///clear
        cteif4: u1 = 0,
        ///CGIF5 [16:16]
        ///Channel 5 Global interrupt
        ///clear
        cgif5: u1 = 0,
        ///CTCIF5 [17:17]
        ///Channel 5 Transfer Complete
        ///clear
        ctcif5: u1 = 0,
        ///CHTIF5 [18:18]
        ///Channel 5 Half Transfer
        ///clear
        chtif5: u1 = 0,
        ///CTEIF5 [19:19]
        ///Channel 5 Transfer Error
        ///clear
        cteif5: u1 = 0,
        ///CGIF6 [20:20]
        ///Channel 6 Global interrupt
        ///clear
        cgif6: u1 = 0,
        ///CTCIF6 [21:21]
        ///Channel 6 Transfer Complete
        ///clear
        ctcif6: u1 = 0,
        ///CHTIF6 [22:22]
        ///Channel 6 Half Transfer
        ///clear
        chtif6: u1 = 0,
        ///CTEIF6 [23:23]
        ///Channel 6 Transfer Error
        ///clear
        cteif6: u1 = 0,
        ///CGIF7 [24:24]
        ///Channel 7 Global interrupt
        ///clear
        cgif7: u1 = 0,
        ///CTCIF7 [25:25]
        ///Channel 7 Transfer Complete
        ///clear
        ctcif7: u1 = 0,
        ///CHTIF7 [26:26]
        ///Channel 7 Half Transfer
        ///clear
        chtif7: u1 = 0,
        ///CTEIF7 [27:27]
        ///Channel 7 Transfer Error
        ///clear
        cteif7: u1 = 0,
        _unused28: u4 = 0,
    };
    ///DMA interrupt flag clear register
    ///(DMA_IFCR)
    pub const ifcr = RegisterRW(void, ifcr_val).init(0x40020400 + 0x4);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr1 = Register(ccr1_val).init(0x40020400 + 0x8);

    //////////////////////////
    ///CNDTR1
    const cndtr1_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 1 number of data
    ///register
    pub const cndtr1 = Register(cndtr1_val).init(0x40020400 + 0xC);

    //////////////////////////
    ///CPAR1
    const cpar1_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 1 peripheral address
    ///register
    pub const cpar1 = Register(cpar1_val).init(0x40020400 + 0x10);

    //////////////////////////
    ///CMAR1
    const cmar1_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 1 memory address
    ///register
    pub const cmar1 = Register(cmar1_val).init(0x40020400 + 0x14);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr2 = Register(ccr2_val).init(0x40020400 + 0x1C);

    //////////////////////////
    ///CNDTR2
    const cndtr2_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 2 number of data
    ///register
    pub const cndtr2 = Register(cndtr2_val).init(0x40020400 + 0x20);

    //////////////////////////
    ///CPAR2
    const cpar2_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 2 peripheral address
    ///register
    pub const cpar2 = Register(cpar2_val).init(0x40020400 + 0x24);

    //////////////////////////
    ///CMAR2
    const cmar2_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 2 memory address
    ///register
    pub const cmar2 = Register(cmar2_val).init(0x40020400 + 0x28);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr3 = Register(ccr3_val).init(0x40020400 + 0x30);

    //////////////////////////
    ///CNDTR3
    const cndtr3_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 3 number of data
    ///register
    pub const cndtr3 = Register(cndtr3_val).init(0x40020400 + 0x34);

    //////////////////////////
    ///CPAR3
    const cpar3_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 3 peripheral address
    ///register
    pub const cpar3 = Register(cpar3_val).init(0x40020400 + 0x38);

    //////////////////////////
    ///CMAR3
    const cmar3_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 3 memory address
    ///register
    pub const cmar3 = Register(cmar3_val).init(0x40020400 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr4 = Register(ccr4_val).init(0x40020400 + 0x44);

    //////////////////////////
    ///CNDTR4
    const cndtr4_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 4 number of data
    ///register
    pub const cndtr4 = Register(cndtr4_val).init(0x40020400 + 0x48);

    //////////////////////////
    ///CPAR4
    const cpar4_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 4 peripheral address
    ///register
    pub const cpar4 = Register(cpar4_val).init(0x40020400 + 0x4C);

    //////////////////////////
    ///CMAR4
    const cmar4_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 4 memory address
    ///register
    pub const cmar4 = Register(cmar4_val).init(0x40020400 + 0x50);

    //////////////////////////
    ///CCR5
    const ccr5_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr5 = Register(ccr5_val).init(0x40020400 + 0x58);

    //////////////////////////
    ///CNDTR5
    const cndtr5_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 5 number of data
    ///register
    pub const cndtr5 = Register(cndtr5_val).init(0x40020400 + 0x5C);

    //////////////////////////
    ///CPAR5
    const cpar5_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 5 peripheral address
    ///register
    pub const cpar5 = Register(cpar5_val).init(0x40020400 + 0x60);

    //////////////////////////
    ///CMAR5
    const cmar5_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 5 memory address
    ///register
    pub const cmar5 = Register(cmar5_val).init(0x40020400 + 0x64);

    //////////////////////////
    ///CCR6
    const ccr6_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr6 = Register(ccr6_val).init(0x40020400 + 0x6C);

    //////////////////////////
    ///CNDTR6
    const cndtr6_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 6 number of data
    ///register
    pub const cndtr6 = Register(cndtr6_val).init(0x40020400 + 0x70);

    //////////////////////////
    ///CPAR6
    const cpar6_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 6 peripheral address
    ///register
    pub const cpar6 = Register(cpar6_val).init(0x40020400 + 0x74);

    //////////////////////////
    ///CMAR6
    const cmar6_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 6 memory address
    ///register
    pub const cmar6 = Register(cmar6_val).init(0x40020400 + 0x78);

    //////////////////////////
    ///CCR7
    const ccr7_val = packed struct {
        ///EN [0:0]
        ///Channel enable
        en: u1 = 0,
        ///TCIE [1:1]
        ///Transfer complete interrupt
        ///enable
        tcie: u1 = 0,
        ///HTIE [2:2]
        ///Half Transfer interrupt
        ///enable
        htie: u1 = 0,
        ///TEIE [3:3]
        ///Transfer error interrupt
        ///enable
        teie: u1 = 0,
        ///DIR [4:4]
        ///Data transfer direction
        dir: u1 = 0,
        ///CIRC [5:5]
        ///Circular mode
        circ: u1 = 0,
        ///PINC [6:6]
        ///Peripheral increment mode
        pinc: u1 = 0,
        ///MINC [7:7]
        ///Memory increment mode
        minc: u1 = 0,
        ///PSIZE [8:9]
        ///Peripheral size
        psize: u2 = 0,
        ///MSIZE [10:11]
        ///Memory size
        msize: u2 = 0,
        ///PL [12:13]
        ///Channel Priority level
        pl: u2 = 0,
        ///MEM2MEM [14:14]
        ///Memory to memory mode
        mem2mem: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA channel configuration register
    ///(DMA_CCR)
    pub const ccr7 = Register(ccr7_val).init(0x40020400 + 0x80);

    //////////////////////////
    ///CNDTR7
    const cndtr7_val = packed struct {
        ///NDT [0:15]
        ///Number of data to transfer
        ndt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA channel 7 number of data
    ///register
    pub const cndtr7 = Register(cndtr7_val).init(0x40020400 + 0x84);

    //////////////////////////
    ///CPAR7
    const cpar7_val = packed struct {
        ///PA [0:31]
        ///Peripheral address
        pa: u32 = 0,
    };
    ///DMA channel 7 peripheral address
    ///register
    pub const cpar7 = Register(cpar7_val).init(0x40020400 + 0x88);

    //////////////////////////
    ///CMAR7
    const cmar7_val = packed struct {
        ///MA [0:31]
        ///Memory address
        ma: u32 = 0,
    };
    ///DMA channel 7 memory address
    ///register
    pub const cmar7 = Register(cmar7_val).init(0x40020400 + 0x8C);
};

///Secure digital input/output
///interface
pub const sdio = struct {

    //////////////////////////
    ///POWER
    const power_val = packed struct {
        ///PWRCTRL [0:1]
        ///PWRCTRL
        pwrctrl: u2 = 0,
        _unused2: u30 = 0,
    };
    ///Bits 1:0 = PWRCTRL: Power supply control
    ///bits
    pub const power = Register(power_val).init(0x40018000 + 0x0);

    //////////////////////////
    ///CLKCR
    const clkcr_val = packed struct {
        ///CLKDIV [0:7]
        ///Clock divide factor
        clkdiv: u8 = 0,
        ///CLKEN [8:8]
        ///Clock enable bit
        clken: u1 = 0,
        ///PWRSAV [9:9]
        ///Power saving configuration
        ///bit
        pwrsav: u1 = 0,
        ///BYPASS [10:10]
        ///Clock divider bypass enable
        ///bit
        bypass: u1 = 0,
        ///WIDBUS [11:12]
        ///Wide bus mode enable bit
        widbus: u2 = 0,
        ///NEGEDGE [13:13]
        ///SDIO_CK dephasing selection
        ///bit
        negedge: u1 = 0,
        ///HWFC_EN [14:14]
        ///HW Flow Control enable
        hwfc_en: u1 = 0,
        _unused15: u17 = 0,
    };
    ///SDI clock control register
    ///(SDIO_CLKCR)
    pub const clkcr = Register(clkcr_val).init(0x40018000 + 0x4);

    //////////////////////////
    ///ARG
    const arg_val = packed struct {
        ///CMDARG [0:31]
        ///Command argument
        cmdarg: u32 = 0,
    };
    ///Bits 31:0 = : Command argument
    pub const arg = Register(arg_val).init(0x40018000 + 0x8);

    //////////////////////////
    ///CMD
    const cmd_val = packed struct {
        ///CMDINDEX [0:5]
        ///CMDINDEX
        cmdindex: u6 = 0,
        ///WAITRESP [6:7]
        ///WAITRESP
        waitresp: u2 = 0,
        ///WAITINT [8:8]
        ///WAITINT
        waitint: u1 = 0,
        ///WAITPEND [9:9]
        ///WAITPEND
        waitpend: u1 = 0,
        ///CPSMEN [10:10]
        ///CPSMEN
        cpsmen: u1 = 0,
        ///SDIOSuspend [11:11]
        ///SDIOSuspend
        sdio_suspend: u1 = 0,
        ///ENCMDcompl [12:12]
        ///ENCMDcompl
        encmdcompl: u1 = 0,
        ///nIEN [13:13]
        ///nIEN
        n_ien: u1 = 0,
        ///CE_ATACMD [14:14]
        ///CE_ATACMD
        ce_atacmd: u1 = 0,
        _unused15: u17 = 0,
    };
    ///SDIO command register
    ///(SDIO_CMD)
    pub const cmd = Register(cmd_val).init(0x40018000 + 0xC);

    //////////////////////////
    ///RESPCMD
    const respcmd_val = packed struct {
        ///RESPCMD [0:5]
        ///RESPCMD
        respcmd: u6 = 0,
        _unused6: u26 = 0,
    };
    ///SDIO command register
    pub const respcmd = RegisterRW(respcmd_val, void).init(0x40018000 + 0x10);

    //////////////////////////
    ///RESPI1
    const respi1_val = packed struct {
        ///CARDSTATUS1 [0:31]
        ///CARDSTATUS1
        cardstatus1: u32 = 0,
    };
    ///Bits 31:0 = CARDSTATUS1
    pub const respi1 = RegisterRW(respi1_val, void).init(0x40018000 + 0x14);

    //////////////////////////
    ///RESP2
    const resp2_val = packed struct {
        ///CARDSTATUS2 [0:31]
        ///CARDSTATUS2
        cardstatus2: u32 = 0,
    };
    ///Bits 31:0 = CARDSTATUS2
    pub const resp2 = RegisterRW(resp2_val, void).init(0x40018000 + 0x18);

    //////////////////////////
    ///RESP3
    const resp3_val = packed struct {
        ///CARDSTATUS3 [0:31]
        ///CARDSTATUS3
        cardstatus3: u32 = 0,
    };
    ///Bits 31:0 = CARDSTATUS3
    pub const resp3 = RegisterRW(resp3_val, void).init(0x40018000 + 0x1C);

    //////////////////////////
    ///RESP4
    const resp4_val = packed struct {
        ///CARDSTATUS4 [0:31]
        ///CARDSTATUS4
        cardstatus4: u32 = 0,
    };
    ///Bits 31:0 = CARDSTATUS4
    pub const resp4 = RegisterRW(resp4_val, void).init(0x40018000 + 0x20);

    //////////////////////////
    ///DTIMER
    const dtimer_val = packed struct {
        ///DATATIME [0:31]
        ///Data timeout period
        datatime: u32 = 0,
    };
    ///Bits 31:0 = DATATIME: Data timeout
    ///period
    pub const dtimer = Register(dtimer_val).init(0x40018000 + 0x24);

    //////////////////////////
    ///DLEN
    const dlen_val = packed struct {
        ///DATALENGTH [0:24]
        ///Data length value
        datalength: u25 = 0,
        _unused25: u7 = 0,
    };
    ///Bits 24:0 = DATALENGTH: Data length
    ///value
    pub const dlen = Register(dlen_val).init(0x40018000 + 0x28);

    //////////////////////////
    ///DCTRL
    const dctrl_val = packed struct {
        ///DTEN [0:0]
        ///DTEN
        dten: u1 = 0,
        ///DTDIR [1:1]
        ///DTDIR
        dtdir: u1 = 0,
        ///DTMODE [2:2]
        ///DTMODE
        dtmode: u1 = 0,
        ///DMAEN [3:3]
        ///DMAEN
        dmaen: u1 = 0,
        ///DBLOCKSIZE [4:7]
        ///DBLOCKSIZE
        dblocksize: u4 = 0,
        ///PWSTART [8:8]
        ///PWSTART
        pwstart: u1 = 0,
        ///PWSTOP [9:9]
        ///PWSTOP
        pwstop: u1 = 0,
        ///RWMOD [10:10]
        ///RWMOD
        rwmod: u1 = 0,
        ///SDIOEN [11:11]
        ///SDIOEN
        sdioen: u1 = 0,
        _unused12: u20 = 0,
    };
    ///SDIO data control register
    ///(SDIO_DCTRL)
    pub const dctrl = Register(dctrl_val).init(0x40018000 + 0x2C);

    //////////////////////////
    ///DCOUNT
    const dcount_val = packed struct {
        ///DATACOUNT [0:24]
        ///Data count value
        datacount: u25 = 0,
        _unused25: u7 = 0,
    };
    ///Bits 24:0 = DATACOUNT: Data count
    ///value
    pub const dcount = RegisterRW(dcount_val, void).init(0x40018000 + 0x30);

    //////////////////////////
    ///STA
    const sta_val = packed struct {
        ///CCRCFAIL [0:0]
        ///CCRCFAIL
        ccrcfail: u1 = 0,
        ///DCRCFAIL [1:1]
        ///DCRCFAIL
        dcrcfail: u1 = 0,
        ///CTIMEOUT [2:2]
        ///CTIMEOUT
        ctimeout: u1 = 0,
        ///DTIMEOUT [3:3]
        ///DTIMEOUT
        dtimeout: u1 = 0,
        ///TXUNDERR [4:4]
        ///TXUNDERR
        txunderr: u1 = 0,
        ///RXOVERR [5:5]
        ///RXOVERR
        rxoverr: u1 = 0,
        ///CMDREND [6:6]
        ///CMDREND
        cmdrend: u1 = 0,
        ///CMDSENT [7:7]
        ///CMDSENT
        cmdsent: u1 = 0,
        ///DATAEND [8:8]
        ///DATAEND
        dataend: u1 = 0,
        ///STBITERR [9:9]
        ///STBITERR
        stbiterr: u1 = 0,
        ///DBCKEND [10:10]
        ///DBCKEND
        dbckend: u1 = 0,
        ///CMDACT [11:11]
        ///CMDACT
        cmdact: u1 = 0,
        ///TXACT [12:12]
        ///TXACT
        txact: u1 = 0,
        ///RXACT [13:13]
        ///RXACT
        rxact: u1 = 0,
        ///TXFIFOHE [14:14]
        ///TXFIFOHE
        txfifohe: u1 = 0,
        ///RXFIFOHF [15:15]
        ///RXFIFOHF
        rxfifohf: u1 = 0,
        ///TXFIFOF [16:16]
        ///TXFIFOF
        txfifof: u1 = 0,
        ///RXFIFOF [17:17]
        ///RXFIFOF
        rxfifof: u1 = 0,
        ///TXFIFOE [18:18]
        ///TXFIFOE
        txfifoe: u1 = 0,
        ///RXFIFOE [19:19]
        ///RXFIFOE
        rxfifoe: u1 = 0,
        ///TXDAVL [20:20]
        ///TXDAVL
        txdavl: u1 = 0,
        ///RXDAVL [21:21]
        ///RXDAVL
        rxdavl: u1 = 0,
        ///SDIOIT [22:22]
        ///SDIOIT
        sdioit: u1 = 0,
        ///CEATAEND [23:23]
        ///CEATAEND
        ceataend: u1 = 0,
        _unused24: u8 = 0,
    };
    ///SDIO status register
    ///(SDIO_STA)
    pub const sta = RegisterRW(sta_val, void).init(0x40018000 + 0x34);

    //////////////////////////
    ///ICR
    const icr_val = packed struct {
        ///CCRCFAILC [0:0]
        ///CCRCFAILC
        ccrcfailc: u1 = 0,
        ///DCRCFAILC [1:1]
        ///DCRCFAILC
        dcrcfailc: u1 = 0,
        ///CTIMEOUTC [2:2]
        ///CTIMEOUTC
        ctimeoutc: u1 = 0,
        ///DTIMEOUTC [3:3]
        ///DTIMEOUTC
        dtimeoutc: u1 = 0,
        ///TXUNDERRC [4:4]
        ///TXUNDERRC
        txunderrc: u1 = 0,
        ///RXOVERRC [5:5]
        ///RXOVERRC
        rxoverrc: u1 = 0,
        ///CMDRENDC [6:6]
        ///CMDRENDC
        cmdrendc: u1 = 0,
        ///CMDSENTC [7:7]
        ///CMDSENTC
        cmdsentc: u1 = 0,
        ///DATAENDC [8:8]
        ///DATAENDC
        dataendc: u1 = 0,
        ///STBITERRC [9:9]
        ///STBITERRC
        stbiterrc: u1 = 0,
        ///DBCKENDC [10:10]
        ///DBCKENDC
        dbckendc: u1 = 0,
        _unused11: u11 = 0,
        ///SDIOITC [22:22]
        ///SDIOITC
        sdioitc: u1 = 0,
        ///CEATAENDC [23:23]
        ///CEATAENDC
        ceataendc: u1 = 0,
        _unused24: u8 = 0,
    };
    ///SDIO interrupt clear register
    ///(SDIO_ICR)
    pub const icr = Register(icr_val).init(0x40018000 + 0x38);

    //////////////////////////
    ///MASK
    const mask_val = packed struct {
        ///CCRCFAILIE [0:0]
        ///CCRCFAILIE
        ccrcfailie: u1 = 0,
        ///DCRCFAILIE [1:1]
        ///DCRCFAILIE
        dcrcfailie: u1 = 0,
        ///CTIMEOUTIE [2:2]
        ///CTIMEOUTIE
        ctimeoutie: u1 = 0,
        ///DTIMEOUTIE [3:3]
        ///DTIMEOUTIE
        dtimeoutie: u1 = 0,
        ///TXUNDERRIE [4:4]
        ///TXUNDERRIE
        txunderrie: u1 = 0,
        ///RXOVERRIE [5:5]
        ///RXOVERRIE
        rxoverrie: u1 = 0,
        ///CMDRENDIE [6:6]
        ///CMDRENDIE
        cmdrendie: u1 = 0,
        ///CMDSENTIE [7:7]
        ///CMDSENTIE
        cmdsentie: u1 = 0,
        ///DATAENDIE [8:8]
        ///DATAENDIE
        dataendie: u1 = 0,
        ///STBITERRIE [9:9]
        ///STBITERRIE
        stbiterrie: u1 = 0,
        ///DBACKENDIE [10:10]
        ///DBACKENDIE
        dbackendie: u1 = 0,
        ///CMDACTIE [11:11]
        ///CMDACTIE
        cmdactie: u1 = 0,
        ///TXACTIE [12:12]
        ///TXACTIE
        txactie: u1 = 0,
        ///RXACTIE [13:13]
        ///RXACTIE
        rxactie: u1 = 0,
        ///TXFIFOHEIE [14:14]
        ///TXFIFOHEIE
        txfifoheie: u1 = 0,
        ///RXFIFOHFIE [15:15]
        ///RXFIFOHFIE
        rxfifohfie: u1 = 0,
        ///TXFIFOFIE [16:16]
        ///TXFIFOFIE
        txfifofie: u1 = 0,
        ///RXFIFOFIE [17:17]
        ///RXFIFOFIE
        rxfifofie: u1 = 0,
        ///TXFIFOEIE [18:18]
        ///TXFIFOEIE
        txfifoeie: u1 = 0,
        ///RXFIFOEIE [19:19]
        ///RXFIFOEIE
        rxfifoeie: u1 = 0,
        ///TXDAVLIE [20:20]
        ///TXDAVLIE
        txdavlie: u1 = 0,
        ///RXDAVLIE [21:21]
        ///RXDAVLIE
        rxdavlie: u1 = 0,
        ///SDIOITIE [22:22]
        ///SDIOITIE
        sdioitie: u1 = 0,
        ///CEATENDIE [23:23]
        ///CEATENDIE
        ceatendie: u1 = 0,
        _unused24: u8 = 0,
    };
    ///SDIO mask register (SDIO_MASK)
    pub const mask = Register(mask_val).init(0x40018000 + 0x3C);

    //////////////////////////
    ///FIFOCNT
    const fifocnt_val = packed struct {
        ///FIF0COUNT [0:23]
        ///FIF0COUNT
        fif0count: u24 = 0,
        _unused24: u8 = 0,
    };
    ///Bits 23:0 = FIFOCOUNT: Remaining number of
    ///words to be written to or read from the
    ///FIFO
    pub const fifocnt = RegisterRW(fifocnt_val, void).init(0x40018000 + 0x48);

    //////////////////////////
    ///FIFO
    const fifo_val = packed struct {
        ///FIFOData [0:31]
        ///FIFOData
        fifodata: u32 = 0,
    };
    ///bits 31:0 = FIFOData: Receive and transmit
    ///FIFO data
    pub const fifo = Register(fifo_val).init(0x40018000 + 0x80);
};

///Real time clock
pub const rtc = struct {

    //////////////////////////
    ///CRH
    const crh_val = packed struct {
        ///SECIE [0:0]
        ///Second interrupt Enable
        secie: u1 = 0,
        ///ALRIE [1:1]
        ///Alarm interrupt Enable
        alrie: u1 = 0,
        ///OWIE [2:2]
        ///Overflow interrupt Enable
        owie: u1 = 0,
        _unused3: u29 = 0,
    };
    ///RTC Control Register High
    pub const crh = Register(crh_val).init(0x40002800 + 0x0);

    //////////////////////////
    ///CRL
    const crl_val = packed struct {
        ///SECF [0:0]
        ///Second Flag
        secf: u1 = 0,
        ///ALRF [1:1]
        ///Alarm Flag
        alrf: u1 = 0,
        ///OWF [2:2]
        ///Overflow Flag
        owf: u1 = 0,
        ///RSF [3:3]
        ///Registers Synchronized
        ///Flag
        rsf: u1 = 0,
        ///CNF [4:4]
        ///Configuration Flag
        cnf: u1 = 0,
        ///RTOFF [5:5]
        ///RTC operation OFF
        rtoff: u1 = 1,
        _unused6: u26 = 0,
    };
    ///RTC Control Register Low
    pub const crl = Register(crl_val).init(0x40002800 + 0x4);

    //////////////////////////
    ///PRLH
    const prlh_val = packed struct {
        ///PRLH [0:3]
        ///RTC Prescaler Load Register
        ///High
        prlh: u4 = 0,
        _unused4: u28 = 0,
    };
    ///RTC Prescaler Load Register
    ///High
    pub const prlh = RegisterRW(void, prlh_val).init(0x40002800 + 0x8);

    //////////////////////////
    ///PRLL
    const prll_val = packed struct {
        ///PRLL [0:15]
        ///RTC Prescaler Divider Register
        ///Low
        prll: u16 = 32768,
        _unused16: u16 = 0,
    };
    ///RTC Prescaler Load Register
    ///Low
    pub const prll = RegisterRW(void, prll_val).init(0x40002800 + 0xC);

    //////////////////////////
    ///DIVH
    const divh_val = packed struct {
        ///DIVH [0:3]
        ///RTC prescaler divider register
        ///high
        divh: u4 = 0,
        _unused4: u28 = 0,
    };
    ///RTC Prescaler Divider Register
    ///High
    pub const divh = RegisterRW(divh_val, void).init(0x40002800 + 0x10);

    //////////////////////////
    ///DIVL
    const divl_val = packed struct {
        ///DIVL [0:15]
        ///RTC prescaler divider register
        ///Low
        divl: u16 = 32768,
        _unused16: u16 = 0,
    };
    ///RTC Prescaler Divider Register
    ///Low
    pub const divl = RegisterRW(divl_val, void).init(0x40002800 + 0x14);

    //////////////////////////
    ///CNTH
    const cnth_val = packed struct {
        ///CNTH [0:15]
        ///RTC counter register high
        cnth: u16 = 0,
        _unused16: u16 = 0,
    };
    ///RTC Counter Register High
    pub const cnth = Register(cnth_val).init(0x40002800 + 0x18);

    //////////////////////////
    ///CNTL
    const cntl_val = packed struct {
        ///CNTL [0:15]
        ///RTC counter register Low
        cntl: u16 = 0,
        _unused16: u16 = 0,
    };
    ///RTC Counter Register Low
    pub const cntl = Register(cntl_val).init(0x40002800 + 0x1C);

    //////////////////////////
    ///ALRH
    const alrh_val = packed struct {
        ///ALRH [0:15]
        ///RTC alarm register high
        alrh: u16 = 65535,
        _unused16: u16 = 0,
    };
    ///RTC Alarm Register High
    pub const alrh = RegisterRW(void, alrh_val).init(0x40002800 + 0x20);

    //////////////////////////
    ///ALRL
    const alrl_val = packed struct {
        ///ALRL [0:15]
        ///RTC alarm register low
        alrl: u16 = 65535,
        _unused16: u16 = 0,
    };
    ///RTC Alarm Register Low
    pub const alrl = RegisterRW(void, alrl_val).init(0x40002800 + 0x24);
};

///Backup registers
pub const bkp = struct {

    //////////////////////////
    ///DR1
    const dr1_val = packed struct {
        ///D1 [0:15]
        ///Backup data
        d1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr1 = Register(dr1_val).init(0x40006C00 + 0x0);

    //////////////////////////
    ///DR2
    const dr2_val = packed struct {
        ///D2 [0:15]
        ///Backup data
        d2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr2 = Register(dr2_val).init(0x40006C00 + 0x4);

    //////////////////////////
    ///DR3
    const dr3_val = packed struct {
        ///D3 [0:15]
        ///Backup data
        d3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr3 = Register(dr3_val).init(0x40006C00 + 0x8);

    //////////////////////////
    ///DR4
    const dr4_val = packed struct {
        ///D4 [0:15]
        ///Backup data
        d4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr4 = Register(dr4_val).init(0x40006C00 + 0xC);

    //////////////////////////
    ///DR5
    const dr5_val = packed struct {
        ///D5 [0:15]
        ///Backup data
        d5: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr5 = Register(dr5_val).init(0x40006C00 + 0x10);

    //////////////////////////
    ///DR6
    const dr6_val = packed struct {
        ///D6 [0:15]
        ///Backup data
        d6: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr6 = Register(dr6_val).init(0x40006C00 + 0x14);

    //////////////////////////
    ///DR7
    const dr7_val = packed struct {
        ///D7 [0:15]
        ///Backup data
        d7: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr7 = Register(dr7_val).init(0x40006C00 + 0x18);

    //////////////////////////
    ///DR8
    const dr8_val = packed struct {
        ///D8 [0:15]
        ///Backup data
        d8: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr8 = Register(dr8_val).init(0x40006C00 + 0x1C);

    //////////////////////////
    ///DR9
    const dr9_val = packed struct {
        ///D9 [0:15]
        ///Backup data
        d9: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr9 = Register(dr9_val).init(0x40006C00 + 0x20);

    //////////////////////////
    ///DR10
    const dr10_val = packed struct {
        ///D10 [0:15]
        ///Backup data
        d10: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr10 = Register(dr10_val).init(0x40006C00 + 0x24);

    //////////////////////////
    ///DR11
    const dr11_val = packed struct {
        ///DR11 [0:15]
        ///Backup data
        dr11: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr11 = Register(dr11_val).init(0x40006C00 + 0x3C);

    //////////////////////////
    ///DR12
    const dr12_val = packed struct {
        ///DR12 [0:15]
        ///Backup data
        dr12: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr12 = Register(dr12_val).init(0x40006C00 + 0x40);

    //////////////////////////
    ///DR13
    const dr13_val = packed struct {
        ///DR13 [0:15]
        ///Backup data
        dr13: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr13 = Register(dr13_val).init(0x40006C00 + 0x44);

    //////////////////////////
    ///DR14
    const dr14_val = packed struct {
        ///D14 [0:15]
        ///Backup data
        d14: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr14 = Register(dr14_val).init(0x40006C00 + 0x48);

    //////////////////////////
    ///DR15
    const dr15_val = packed struct {
        ///D15 [0:15]
        ///Backup data
        d15: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr15 = Register(dr15_val).init(0x40006C00 + 0x4C);

    //////////////////////////
    ///DR16
    const dr16_val = packed struct {
        ///D16 [0:15]
        ///Backup data
        d16: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr16 = Register(dr16_val).init(0x40006C00 + 0x50);

    //////////////////////////
    ///DR17
    const dr17_val = packed struct {
        ///D17 [0:15]
        ///Backup data
        d17: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr17 = Register(dr17_val).init(0x40006C00 + 0x54);

    //////////////////////////
    ///DR18
    const dr18_val = packed struct {
        ///D18 [0:15]
        ///Backup data
        d18: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr18 = Register(dr18_val).init(0x40006C00 + 0x58);

    //////////////////////////
    ///DR19
    const dr19_val = packed struct {
        ///D19 [0:15]
        ///Backup data
        d19: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr19 = Register(dr19_val).init(0x40006C00 + 0x5C);

    //////////////////////////
    ///DR20
    const dr20_val = packed struct {
        ///D20 [0:15]
        ///Backup data
        d20: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr20 = Register(dr20_val).init(0x40006C00 + 0x60);

    //////////////////////////
    ///DR21
    const dr21_val = packed struct {
        ///D21 [0:15]
        ///Backup data
        d21: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr21 = Register(dr21_val).init(0x40006C00 + 0x64);

    //////////////////////////
    ///DR22
    const dr22_val = packed struct {
        ///D22 [0:15]
        ///Backup data
        d22: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr22 = Register(dr22_val).init(0x40006C00 + 0x68);

    //////////////////////////
    ///DR23
    const dr23_val = packed struct {
        ///D23 [0:15]
        ///Backup data
        d23: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr23 = Register(dr23_val).init(0x40006C00 + 0x6C);

    //////////////////////////
    ///DR24
    const dr24_val = packed struct {
        ///D24 [0:15]
        ///Backup data
        d24: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr24 = Register(dr24_val).init(0x40006C00 + 0x70);

    //////////////////////////
    ///DR25
    const dr25_val = packed struct {
        ///D25 [0:15]
        ///Backup data
        d25: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr25 = Register(dr25_val).init(0x40006C00 + 0x74);

    //////////////////////////
    ///DR26
    const dr26_val = packed struct {
        ///D26 [0:15]
        ///Backup data
        d26: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr26 = Register(dr26_val).init(0x40006C00 + 0x78);

    //////////////////////////
    ///DR27
    const dr27_val = packed struct {
        ///D27 [0:15]
        ///Backup data
        d27: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr27 = Register(dr27_val).init(0x40006C00 + 0x7C);

    //////////////////////////
    ///DR28
    const dr28_val = packed struct {
        ///D28 [0:15]
        ///Backup data
        d28: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr28 = Register(dr28_val).init(0x40006C00 + 0x80);

    //////////////////////////
    ///DR29
    const dr29_val = packed struct {
        ///D29 [0:15]
        ///Backup data
        d29: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr29 = Register(dr29_val).init(0x40006C00 + 0x84);

    //////////////////////////
    ///DR30
    const dr30_val = packed struct {
        ///D30 [0:15]
        ///Backup data
        d30: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr30 = Register(dr30_val).init(0x40006C00 + 0x88);

    //////////////////////////
    ///DR31
    const dr31_val = packed struct {
        ///D31 [0:15]
        ///Backup data
        d31: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr31 = Register(dr31_val).init(0x40006C00 + 0x8C);

    //////////////////////////
    ///DR32
    const dr32_val = packed struct {
        ///D32 [0:15]
        ///Backup data
        d32: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr32 = Register(dr32_val).init(0x40006C00 + 0x90);

    //////////////////////////
    ///DR33
    const dr33_val = packed struct {
        ///D33 [0:15]
        ///Backup data
        d33: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr33 = Register(dr33_val).init(0x40006C00 + 0x94);

    //////////////////////////
    ///DR34
    const dr34_val = packed struct {
        ///D34 [0:15]
        ///Backup data
        d34: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr34 = Register(dr34_val).init(0x40006C00 + 0x98);

    //////////////////////////
    ///DR35
    const dr35_val = packed struct {
        ///D35 [0:15]
        ///Backup data
        d35: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr35 = Register(dr35_val).init(0x40006C00 + 0x9C);

    //////////////////////////
    ///DR36
    const dr36_val = packed struct {
        ///D36 [0:15]
        ///Backup data
        d36: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr36 = Register(dr36_val).init(0x40006C00 + 0xA0);

    //////////////////////////
    ///DR37
    const dr37_val = packed struct {
        ///D37 [0:15]
        ///Backup data
        d37: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr37 = Register(dr37_val).init(0x40006C00 + 0xA4);

    //////////////////////////
    ///DR38
    const dr38_val = packed struct {
        ///D38 [0:15]
        ///Backup data
        d38: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr38 = Register(dr38_val).init(0x40006C00 + 0xA8);

    //////////////////////////
    ///DR39
    const dr39_val = packed struct {
        ///D39 [0:15]
        ///Backup data
        d39: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr39 = Register(dr39_val).init(0x40006C00 + 0xAC);

    //////////////////////////
    ///DR40
    const dr40_val = packed struct {
        ///D40 [0:15]
        ///Backup data
        d40: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr40 = Register(dr40_val).init(0x40006C00 + 0xB0);

    //////////////////////////
    ///DR41
    const dr41_val = packed struct {
        ///D41 [0:15]
        ///Backup data
        d41: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr41 = Register(dr41_val).init(0x40006C00 + 0xB4);

    //////////////////////////
    ///DR42
    const dr42_val = packed struct {
        ///D42 [0:15]
        ///Backup data
        d42: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Backup data register (BKP_DR)
    pub const dr42 = Register(dr42_val).init(0x40006C00 + 0xB8);

    //////////////////////////
    ///RTCCR
    const rtccr_val = packed struct {
        ///CAL [0:6]
        ///Calibration value
        cal: u7 = 0,
        ///CCO [7:7]
        ///Calibration Clock Output
        cco: u1 = 0,
        ///ASOE [8:8]
        ///Alarm or second output
        ///enable
        asoe: u1 = 0,
        ///ASOS [9:9]
        ///Alarm or second output
        ///selection
        asos: u1 = 0,
        _unused10: u22 = 0,
    };
    ///RTC clock calibration register
    ///(BKP_RTCCR)
    pub const rtccr = Register(rtccr_val).init(0x40006C00 + 0x28);

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///TPE [0:0]
        ///Tamper pin enable
        tpe: u1 = 0,
        ///TPAL [1:1]
        ///Tamper pin active level
        tpal: u1 = 0,
        _unused2: u30 = 0,
    };
    ///Backup control register
    ///(BKP_CR)
    pub const cr = Register(cr_val).init(0x40006C00 + 0x2C);

    //////////////////////////
    ///CSR
    const csr_val = packed struct {
        ///CTE [0:0]
        ///Clear Tamper event
        cte: u1 = 0,
        ///CTI [1:1]
        ///Clear Tamper Interrupt
        cti: u1 = 0,
        ///TPIE [2:2]
        ///Tamper Pin interrupt
        ///enable
        tpie: u1 = 0,
        _unused3: u5 = 0,
        ///TEF [8:8]
        ///Tamper Event Flag
        tef: u1 = 0,
        ///TIF [9:9]
        ///Tamper Interrupt Flag
        tif: u1 = 0,
        _unused10: u22 = 0,
    };
    ///BKP_CSR control/status register
    ///(BKP_CSR)
    pub const csr = Register(csr_val).init(0x40006C00 + 0x30);
};

///Independent watchdog
pub const iwdg = struct {

    //////////////////////////
    ///KR
    const kr_val = packed struct {
        ///KEY [0:15]
        ///Key value
        key: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Key register (IWDG_KR)
    pub const kr = RegisterRW(void, kr_val).init(0x40003000 + 0x0);

    //////////////////////////
    ///PR
    const pr_val = packed struct {
        ///PR [0:2]
        ///Prescaler divider
        pr: u3 = 0,
        _unused3: u29 = 0,
    };
    ///Prescaler register (IWDG_PR)
    pub const pr = Register(pr_val).init(0x40003000 + 0x4);

    //////////////////////////
    ///RLR
    const rlr_val = packed struct {
        ///RL [0:11]
        ///Watchdog counter reload
        ///value
        rl: u12 = 4095,
        _unused12: u20 = 0,
    };
    ///Reload register (IWDG_RLR)
    pub const rlr = Register(rlr_val).init(0x40003000 + 0x8);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///PVU [0:0]
        ///Watchdog prescaler value
        ///update
        pvu: u1 = 0,
        ///RVU [1:1]
        ///Watchdog counter reload value
        ///update
        rvu: u1 = 0,
        _unused2: u30 = 0,
    };
    ///Status register (IWDG_SR)
    pub const sr = RegisterRW(sr_val, void).init(0x40003000 + 0xC);
};

///Window watchdog
pub const wwdg = struct {

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///T [0:6]
        ///7-bit counter (MSB to LSB)
        t: u7 = 127,
        ///WDGA [7:7]
        ///Activation bit
        wdga: u1 = 0,
        _unused8: u24 = 0,
    };
    ///Control register (WWDG_CR)
    pub const cr = Register(cr_val).init(0x40002C00 + 0x0);

    //////////////////////////
    ///CFR
    const cfr_val = packed struct {
        ///W [0:6]
        ///7-bit window value
        w: u7 = 127,
        ///WDGTB [7:8]
        ///Timer Base
        wdgtb: u2 = 0,
        ///EWI [9:9]
        ///Early Wakeup Interrupt
        ewi: u1 = 0,
        _unused10: u22 = 0,
    };
    ///Configuration register
    ///(WWDG_CFR)
    pub const cfr = Register(cfr_val).init(0x40002C00 + 0x4);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///EWI [0:0]
        ///Early Wakeup Interrupt
        ewi: u1 = 0,
        _unused1: u31 = 0,
    };
    ///Status register (WWDG_SR)
    pub const sr = Register(sr_val).init(0x40002C00 + 0x8);
};

///Advanced timer
pub const tim1 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        ///DIR [4:4]
        ///Direction
        dir: u1 = 0,
        ///CMS [5:6]
        ///Center-aligned mode
        ///selection
        cms: u2 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40012C00 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///CCPC [0:0]
        ///Capture/compare preloaded
        ///control
        ccpc: u1 = 0,
        _unused1: u1 = 0,
        ///CCUS [2:2]
        ///Capture/compare control update
        ///selection
        ccus: u1 = 0,
        ///CCDS [3:3]
        ///Capture/compare DMA
        ///selection
        ccds: u1 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        ///TI1S [7:7]
        ///TI1 selection
        ti1s: u1 = 0,
        ///OIS1 [8:8]
        ///Output Idle state 1
        ois1: u1 = 0,
        ///OIS1N [9:9]
        ///Output Idle state 1
        ois1n: u1 = 0,
        ///OIS2 [10:10]
        ///Output Idle state 2
        ois2: u1 = 0,
        ///OIS2N [11:11]
        ///Output Idle state 2
        ois2n: u1 = 0,
        ///OIS3 [12:12]
        ///Output Idle state 3
        ois3: u1 = 0,
        ///OIS3N [13:13]
        ///Output Idle state 3
        ois3n: u1 = 0,
        ///OIS4 [14:14]
        ///Output Idle state 4
        ois4: u1 = 0,
        _unused15: u17 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40012C00 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        ///ETF [8:11]
        ///External trigger filter
        etf: u4 = 0,
        ///ETPS [12:13]
        ///External trigger prescaler
        etps: u2 = 0,
        ///ECE [14:14]
        ///External clock enable
        ece: u1 = 0,
        ///ETP [15:15]
        ///External trigger polarity
        etp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40012C00 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        ///CC3IE [3:3]
        ///Capture/Compare 3 interrupt
        ///enable
        cc3ie: u1 = 0,
        ///CC4IE [4:4]
        ///Capture/Compare 4 interrupt
        ///enable
        cc4ie: u1 = 0,
        ///COMIE [5:5]
        ///COM interrupt enable
        comie: u1 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        ///BIE [7:7]
        ///Break interrupt enable
        bie: u1 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        ///CC1DE [9:9]
        ///Capture/Compare 1 DMA request
        ///enable
        cc1de: u1 = 0,
        ///CC2DE [10:10]
        ///Capture/Compare 2 DMA request
        ///enable
        cc2de: u1 = 0,
        ///CC3DE [11:11]
        ///Capture/Compare 3 DMA request
        ///enable
        cc3de: u1 = 0,
        ///CC4DE [12:12]
        ///Capture/Compare 4 DMA request
        ///enable
        cc4de: u1 = 0,
        ///COMDE [13:13]
        ///COM DMA request enable
        comde: u1 = 0,
        ///TDE [14:14]
        ///Trigger DMA request enable
        tde: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40012C00 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        ///CC3IF [3:3]
        ///Capture/Compare 3 interrupt
        ///flag
        cc3if: u1 = 0,
        ///CC4IF [4:4]
        ///Capture/Compare 4 interrupt
        ///flag
        cc4if: u1 = 0,
        ///COMIF [5:5]
        ///COM interrupt flag
        comif: u1 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        ///BIF [7:7]
        ///Break interrupt flag
        bif: u1 = 0,
        _unused8: u1 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        ///CC3OF [11:11]
        ///Capture/Compare 3 overcapture
        ///flag
        cc3of: u1 = 0,
        ///CC4OF [12:12]
        ///Capture/Compare 4 overcapture
        ///flag
        cc4of: u1 = 0,
        _unused13: u19 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40012C00 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        ///CC3G [3:3]
        ///Capture/compare 3
        ///generation
        cc3g: u1 = 0,
        ///CC4G [4:4]
        ///Capture/compare 4
        ///generation
        cc4g: u1 = 0,
        ///COMG [5:5]
        ///Capture/Compare control update
        ///generation
        comg: u1 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        ///BG [7:7]
        ///Break generation
        bg: u1 = 0,
        _unused8: u24 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40012C00 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output Compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        ///OC1CE [7:7]
        ///Output Compare 1 clear
        ///enable
        oc1ce: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output Compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output Compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output Compare 2 mode
        oc2m: u3 = 0,
        ///OC2CE [15:15]
        ///Output Compare 2 clear
        ///enable
        oc2ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40012C00 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///ICPCS [2:3]
        ///Input capture 1 prescaler
        icpcs: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PCS [10:11]
        ///Input capture 2 prescaler
        ic2pcs: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40012C00 + 0x18);

    //////////////////////////
    ///CCMR2_Output
    const ccmr2_output_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///OC3FE [2:2]
        ///Output compare 3 fast
        ///enable
        oc3fe: u1 = 0,
        ///OC3PE [3:3]
        ///Output compare 3 preload
        ///enable
        oc3pe: u1 = 0,
        ///OC3M [4:6]
        ///Output compare 3 mode
        oc3m: u3 = 0,
        ///OC3CE [7:7]
        ///Output compare 3 clear
        ///enable
        oc3ce: u1 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///OC4FE [10:10]
        ///Output compare 4 fast
        ///enable
        oc4fe: u1 = 0,
        ///OC4PE [11:11]
        ///Output compare 4 preload
        ///enable
        oc4pe: u1 = 0,
        ///OC4M [12:14]
        ///Output compare 4 mode
        oc4m: u3 = 0,
        ///OC4CE [15:15]
        ///Output compare 4 clear
        ///enable
        oc4ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr2_output = Register(ccmr2_output_val).init(0x40012C00 + 0x1C);

    //////////////////////////
    ///CCMR2_Input
    const ccmr2_input_val = packed struct {
        ///CC3S [0:1]
        ///Capture/compare 3
        ///selection
        cc3s: u2 = 0,
        ///IC3PSC [2:3]
        ///Input capture 3 prescaler
        ic3psc: u2 = 0,
        ///IC3F [4:7]
        ///Input capture 3 filter
        ic3f: u4 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///IC4PSC [10:11]
        ///Input capture 4 prescaler
        ic4psc: u2 = 0,
        ///IC4F [12:15]
        ///Input capture 4 filter
        ic4f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (input
    ///mode)
    pub const ccmr2_input = Register(ccmr2_input_val).init(0x40012C00 + 0x1C);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        ///CC1NE [2:2]
        ///Capture/Compare 1 complementary output
        ///enable
        cc1ne: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        ///CC2NE [6:6]
        ///Capture/Compare 2 complementary output
        ///enable
        cc2ne: u1 = 0,
        ///CC2NP [7:7]
        ///Capture/Compare 2 output
        ///Polarity
        cc2np: u1 = 0,
        ///CC3E [8:8]
        ///Capture/Compare 3 output
        ///enable
        cc3e: u1 = 0,
        ///CC3P [9:9]
        ///Capture/Compare 3 output
        ///Polarity
        cc3p: u1 = 0,
        ///CC3NE [10:10]
        ///Capture/Compare 3 complementary output
        ///enable
        cc3ne: u1 = 0,
        ///CC3NP [11:11]
        ///Capture/Compare 3 output
        ///Polarity
        cc3np: u1 = 0,
        ///CC4E [12:12]
        ///Capture/Compare 4 output
        ///enable
        cc4e: u1 = 0,
        ///CC4P [13:13]
        ///Capture/Compare 3 output
        ///Polarity
        cc4p: u1 = 0,
        _unused14: u18 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40012C00 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40012C00 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40012C00 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40012C00 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40012C00 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40012C00 + 0x38);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///CCR3 [0:15]
        ///Capture/Compare value
        ccr3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 3
    pub const ccr3 = Register(ccr3_val).init(0x40012C00 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///CCR4 [0:15]
        ///Capture/Compare value
        ccr4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 4
    pub const ccr4 = Register(ccr4_val).init(0x40012C00 + 0x40);

    //////////////////////////
    ///DCR
    const dcr_val = packed struct {
        ///DBA [0:4]
        ///DMA base address
        dba: u5 = 0,
        _unused5: u3 = 0,
        ///DBL [8:12]
        ///DMA burst length
        dbl: u5 = 0,
        _unused13: u19 = 0,
    };
    ///DMA control register
    pub const dcr = Register(dcr_val).init(0x40012C00 + 0x48);

    //////////////////////////
    ///DMAR
    const dmar_val = packed struct {
        ///DMAB [0:15]
        ///DMA register for burst
        ///accesses
        dmab: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA address for full transfer
    pub const dmar = Register(dmar_val).init(0x40012C00 + 0x4C);

    //////////////////////////
    ///RCR
    const rcr_val = packed struct {
        ///REP [0:7]
        ///Repetition counter value
        rep: u8 = 0,
        _unused8: u24 = 0,
    };
    ///repetition counter register
    pub const rcr = Register(rcr_val).init(0x40012C00 + 0x30);

    //////////////////////////
    ///BDTR
    const bdtr_val = packed struct {
        ///DTG [0:7]
        ///Dead-time generator setup
        dtg: u8 = 0,
        ///LOCK [8:9]
        ///Lock configuration
        lock: u2 = 0,
        ///OSSI [10:10]
        ///Off-state selection for Idle
        ///mode
        ossi: u1 = 0,
        ///OSSR [11:11]
        ///Off-state selection for Run
        ///mode
        ossr: u1 = 0,
        ///BKE [12:12]
        ///Break enable
        bke: u1 = 0,
        ///BKP [13:13]
        ///Break polarity
        bkp: u1 = 0,
        ///AOE [14:14]
        ///Automatic output enable
        aoe: u1 = 0,
        ///MOE [15:15]
        ///Main output enable
        moe: u1 = 0,
        _unused16: u16 = 0,
    };
    ///break and dead-time register
    pub const bdtr = Register(bdtr_val).init(0x40012C00 + 0x44);
};

///Advanced timer
pub const tim8 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        ///DIR [4:4]
        ///Direction
        dir: u1 = 0,
        ///CMS [5:6]
        ///Center-aligned mode
        ///selection
        cms: u2 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40013400 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///CCPC [0:0]
        ///Capture/compare preloaded
        ///control
        ccpc: u1 = 0,
        _unused1: u1 = 0,
        ///CCUS [2:2]
        ///Capture/compare control update
        ///selection
        ccus: u1 = 0,
        ///CCDS [3:3]
        ///Capture/compare DMA
        ///selection
        ccds: u1 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        ///TI1S [7:7]
        ///TI1 selection
        ti1s: u1 = 0,
        ///OIS1 [8:8]
        ///Output Idle state 1
        ois1: u1 = 0,
        ///OIS1N [9:9]
        ///Output Idle state 1
        ois1n: u1 = 0,
        ///OIS2 [10:10]
        ///Output Idle state 2
        ois2: u1 = 0,
        ///OIS2N [11:11]
        ///Output Idle state 2
        ois2n: u1 = 0,
        ///OIS3 [12:12]
        ///Output Idle state 3
        ois3: u1 = 0,
        ///OIS3N [13:13]
        ///Output Idle state 3
        ois3n: u1 = 0,
        ///OIS4 [14:14]
        ///Output Idle state 4
        ois4: u1 = 0,
        _unused15: u17 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40013400 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        ///ETF [8:11]
        ///External trigger filter
        etf: u4 = 0,
        ///ETPS [12:13]
        ///External trigger prescaler
        etps: u2 = 0,
        ///ECE [14:14]
        ///External clock enable
        ece: u1 = 0,
        ///ETP [15:15]
        ///External trigger polarity
        etp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40013400 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        ///CC3IE [3:3]
        ///Capture/Compare 3 interrupt
        ///enable
        cc3ie: u1 = 0,
        ///CC4IE [4:4]
        ///Capture/Compare 4 interrupt
        ///enable
        cc4ie: u1 = 0,
        ///COMIE [5:5]
        ///COM interrupt enable
        comie: u1 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        ///BIE [7:7]
        ///Break interrupt enable
        bie: u1 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        ///CC1DE [9:9]
        ///Capture/Compare 1 DMA request
        ///enable
        cc1de: u1 = 0,
        ///CC2DE [10:10]
        ///Capture/Compare 2 DMA request
        ///enable
        cc2de: u1 = 0,
        ///CC3DE [11:11]
        ///Capture/Compare 3 DMA request
        ///enable
        cc3de: u1 = 0,
        ///CC4DE [12:12]
        ///Capture/Compare 4 DMA request
        ///enable
        cc4de: u1 = 0,
        ///COMDE [13:13]
        ///COM DMA request enable
        comde: u1 = 0,
        ///TDE [14:14]
        ///Trigger DMA request enable
        tde: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40013400 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        ///CC3IF [3:3]
        ///Capture/Compare 3 interrupt
        ///flag
        cc3if: u1 = 0,
        ///CC4IF [4:4]
        ///Capture/Compare 4 interrupt
        ///flag
        cc4if: u1 = 0,
        ///COMIF [5:5]
        ///COM interrupt flag
        comif: u1 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        ///BIF [7:7]
        ///Break interrupt flag
        bif: u1 = 0,
        _unused8: u1 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        ///CC3OF [11:11]
        ///Capture/Compare 3 overcapture
        ///flag
        cc3of: u1 = 0,
        ///CC4OF [12:12]
        ///Capture/Compare 4 overcapture
        ///flag
        cc4of: u1 = 0,
        _unused13: u19 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40013400 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        ///CC3G [3:3]
        ///Capture/compare 3
        ///generation
        cc3g: u1 = 0,
        ///CC4G [4:4]
        ///Capture/compare 4
        ///generation
        cc4g: u1 = 0,
        ///COMG [5:5]
        ///Capture/Compare control update
        ///generation
        comg: u1 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        ///BG [7:7]
        ///Break generation
        bg: u1 = 0,
        _unused8: u24 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40013400 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output Compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        ///OC1CE [7:7]
        ///Output Compare 1 clear
        ///enable
        oc1ce: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output Compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output Compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output Compare 2 mode
        oc2m: u3 = 0,
        ///OC2CE [15:15]
        ///Output Compare 2 clear
        ///enable
        oc2ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40013400 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///ICPCS [2:3]
        ///Input capture 1 prescaler
        icpcs: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PCS [10:11]
        ///Input capture 2 prescaler
        ic2pcs: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40013400 + 0x18);

    //////////////////////////
    ///CCMR2_Output
    const ccmr2_output_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///OC3FE [2:2]
        ///Output compare 3 fast
        ///enable
        oc3fe: u1 = 0,
        ///OC3PE [3:3]
        ///Output compare 3 preload
        ///enable
        oc3pe: u1 = 0,
        ///OC3M [4:6]
        ///Output compare 3 mode
        oc3m: u3 = 0,
        ///OC3CE [7:7]
        ///Output compare 3 clear
        ///enable
        oc3ce: u1 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///OC4FE [10:10]
        ///Output compare 4 fast
        ///enable
        oc4fe: u1 = 0,
        ///OC4PE [11:11]
        ///Output compare 4 preload
        ///enable
        oc4pe: u1 = 0,
        ///OC4M [12:14]
        ///Output compare 4 mode
        oc4m: u3 = 0,
        ///OC4CE [15:15]
        ///Output compare 4 clear
        ///enable
        oc4ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr2_output = Register(ccmr2_output_val).init(0x40013400 + 0x1C);

    //////////////////////////
    ///CCMR2_Input
    const ccmr2_input_val = packed struct {
        ///CC3S [0:1]
        ///Capture/compare 3
        ///selection
        cc3s: u2 = 0,
        ///IC3PSC [2:3]
        ///Input capture 3 prescaler
        ic3psc: u2 = 0,
        ///IC3F [4:7]
        ///Input capture 3 filter
        ic3f: u4 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///IC4PSC [10:11]
        ///Input capture 4 prescaler
        ic4psc: u2 = 0,
        ///IC4F [12:15]
        ///Input capture 4 filter
        ic4f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (input
    ///mode)
    pub const ccmr2_input = Register(ccmr2_input_val).init(0x40013400 + 0x1C);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        ///CC1NE [2:2]
        ///Capture/Compare 1 complementary output
        ///enable
        cc1ne: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        ///CC2NE [6:6]
        ///Capture/Compare 2 complementary output
        ///enable
        cc2ne: u1 = 0,
        ///CC2NP [7:7]
        ///Capture/Compare 2 output
        ///Polarity
        cc2np: u1 = 0,
        ///CC3E [8:8]
        ///Capture/Compare 3 output
        ///enable
        cc3e: u1 = 0,
        ///CC3P [9:9]
        ///Capture/Compare 3 output
        ///Polarity
        cc3p: u1 = 0,
        ///CC3NE [10:10]
        ///Capture/Compare 3 complementary output
        ///enable
        cc3ne: u1 = 0,
        ///CC3NP [11:11]
        ///Capture/Compare 3 output
        ///Polarity
        cc3np: u1 = 0,
        ///CC4E [12:12]
        ///Capture/Compare 4 output
        ///enable
        cc4e: u1 = 0,
        ///CC4P [13:13]
        ///Capture/Compare 3 output
        ///Polarity
        cc4p: u1 = 0,
        _unused14: u18 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40013400 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40013400 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40013400 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40013400 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40013400 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40013400 + 0x38);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///CCR3 [0:15]
        ///Capture/Compare value
        ccr3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 3
    pub const ccr3 = Register(ccr3_val).init(0x40013400 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///CCR4 [0:15]
        ///Capture/Compare value
        ccr4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 4
    pub const ccr4 = Register(ccr4_val).init(0x40013400 + 0x40);

    //////////////////////////
    ///DCR
    const dcr_val = packed struct {
        ///DBA [0:4]
        ///DMA base address
        dba: u5 = 0,
        _unused5: u3 = 0,
        ///DBL [8:12]
        ///DMA burst length
        dbl: u5 = 0,
        _unused13: u19 = 0,
    };
    ///DMA control register
    pub const dcr = Register(dcr_val).init(0x40013400 + 0x48);

    //////////////////////////
    ///DMAR
    const dmar_val = packed struct {
        ///DMAB [0:15]
        ///DMA register for burst
        ///accesses
        dmab: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA address for full transfer
    pub const dmar = Register(dmar_val).init(0x40013400 + 0x4C);

    //////////////////////////
    ///RCR
    const rcr_val = packed struct {
        ///REP [0:7]
        ///Repetition counter value
        rep: u8 = 0,
        _unused8: u24 = 0,
    };
    ///repetition counter register
    pub const rcr = Register(rcr_val).init(0x40013400 + 0x30);

    //////////////////////////
    ///BDTR
    const bdtr_val = packed struct {
        ///DTG [0:7]
        ///Dead-time generator setup
        dtg: u8 = 0,
        ///LOCK [8:9]
        ///Lock configuration
        lock: u2 = 0,
        ///OSSI [10:10]
        ///Off-state selection for Idle
        ///mode
        ossi: u1 = 0,
        ///OSSR [11:11]
        ///Off-state selection for Run
        ///mode
        ossr: u1 = 0,
        ///BKE [12:12]
        ///Break enable
        bke: u1 = 0,
        ///BKP [13:13]
        ///Break polarity
        bkp: u1 = 0,
        ///AOE [14:14]
        ///Automatic output enable
        aoe: u1 = 0,
        ///MOE [15:15]
        ///Main output enable
        moe: u1 = 0,
        _unused16: u16 = 0,
    };
    ///break and dead-time register
    pub const bdtr = Register(bdtr_val).init(0x40013400 + 0x44);
};

///General purpose timer
pub const tim2 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        ///DIR [4:4]
        ///Direction
        dir: u1 = 0,
        ///CMS [5:6]
        ///Center-aligned mode
        ///selection
        cms: u2 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40000000 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u3 = 0,
        ///CCDS [3:3]
        ///Capture/compare DMA
        ///selection
        ccds: u1 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        ///TI1S [7:7]
        ///TI1 selection
        ti1s: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40000000 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        ///ETF [8:11]
        ///External trigger filter
        etf: u4 = 0,
        ///ETPS [12:13]
        ///External trigger prescaler
        etps: u2 = 0,
        ///ECE [14:14]
        ///External clock enable
        ece: u1 = 0,
        ///ETP [15:15]
        ///External trigger polarity
        etp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40000000 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        ///CC3IE [3:3]
        ///Capture/Compare 3 interrupt
        ///enable
        cc3ie: u1 = 0,
        ///CC4IE [4:4]
        ///Capture/Compare 4 interrupt
        ///enable
        cc4ie: u1 = 0,
        _unused5: u1 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        _unused7: u1 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        ///CC1DE [9:9]
        ///Capture/Compare 1 DMA request
        ///enable
        cc1de: u1 = 0,
        ///CC2DE [10:10]
        ///Capture/Compare 2 DMA request
        ///enable
        cc2de: u1 = 0,
        ///CC3DE [11:11]
        ///Capture/Compare 3 DMA request
        ///enable
        cc3de: u1 = 0,
        ///CC4DE [12:12]
        ///Capture/Compare 4 DMA request
        ///enable
        cc4de: u1 = 0,
        _unused13: u1 = 0,
        ///TDE [14:14]
        ///Trigger DMA request enable
        tde: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40000000 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        ///CC3IF [3:3]
        ///Capture/Compare 3 interrupt
        ///flag
        cc3if: u1 = 0,
        ///CC4IF [4:4]
        ///Capture/Compare 4 interrupt
        ///flag
        cc4if: u1 = 0,
        _unused5: u1 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        _unused7: u2 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        ///CC3OF [11:11]
        ///Capture/Compare 3 overcapture
        ///flag
        cc3of: u1 = 0,
        ///CC4OF [12:12]
        ///Capture/Compare 4 overcapture
        ///flag
        cc4of: u1 = 0,
        _unused13: u19 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40000000 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        ///CC3G [3:3]
        ///Capture/compare 3
        ///generation
        cc3g: u1 = 0,
        ///CC4G [4:4]
        ///Capture/compare 4
        ///generation
        cc4g: u1 = 0,
        _unused5: u1 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        _unused7: u25 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40000000 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output compare 1 mode
        oc1m: u3 = 0,
        ///OC1CE [7:7]
        ///Output compare 1 clear
        ///enable
        oc1ce: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output compare 2 mode
        oc2m: u3 = 0,
        ///OC2CE [15:15]
        ///Output compare 2 clear
        ///enable
        oc2ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40000000 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PSC [10:11]
        ///Input capture 2 prescaler
        ic2psc: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40000000 + 0x18);

    //////////////////////////
    ///CCMR2_Output
    const ccmr2_output_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///OC3FE [2:2]
        ///Output compare 3 fast
        ///enable
        oc3fe: u1 = 0,
        ///OC3PE [3:3]
        ///Output compare 3 preload
        ///enable
        oc3pe: u1 = 0,
        ///OC3M [4:6]
        ///Output compare 3 mode
        oc3m: u3 = 0,
        ///OC3CE [7:7]
        ///Output compare 3 clear
        ///enable
        oc3ce: u1 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///OC4FE [10:10]
        ///Output compare 4 fast
        ///enable
        oc4fe: u1 = 0,
        ///OC4PE [11:11]
        ///Output compare 4 preload
        ///enable
        oc4pe: u1 = 0,
        ///OC4M [12:14]
        ///Output compare 4 mode
        oc4m: u3 = 0,
        ///O24CE [15:15]
        ///Output compare 4 clear
        ///enable
        o24ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (output
    ///mode)
    pub const ccmr2_output = Register(ccmr2_output_val).init(0x40000000 + 0x1C);

    //////////////////////////
    ///CCMR2_Input
    const ccmr2_input_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///IC3PSC [2:3]
        ///Input capture 3 prescaler
        ic3psc: u2 = 0,
        ///IC3F [4:7]
        ///Input capture 3 filter
        ic3f: u4 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///IC4PSC [10:11]
        ///Input capture 4 prescaler
        ic4psc: u2 = 0,
        ///IC4F [12:15]
        ///Input capture 4 filter
        ic4f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (input
    ///mode)
    pub const ccmr2_input = Register(ccmr2_input_val).init(0x40000000 + 0x1C);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u2 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        _unused6: u2 = 0,
        ///CC3E [8:8]
        ///Capture/Compare 3 output
        ///enable
        cc3e: u1 = 0,
        ///CC3P [9:9]
        ///Capture/Compare 3 output
        ///Polarity
        cc3p: u1 = 0,
        _unused10: u2 = 0,
        ///CC4E [12:12]
        ///Capture/Compare 4 output
        ///enable
        cc4e: u1 = 0,
        ///CC4P [13:13]
        ///Capture/Compare 3 output
        ///Polarity
        cc4p: u1 = 0,
        _unused14: u18 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40000000 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40000000 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40000000 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40000000 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40000000 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40000000 + 0x38);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///CCR3 [0:15]
        ///Capture/Compare value
        ccr3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 3
    pub const ccr3 = Register(ccr3_val).init(0x40000000 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///CCR4 [0:15]
        ///Capture/Compare value
        ccr4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 4
    pub const ccr4 = Register(ccr4_val).init(0x40000000 + 0x40);

    //////////////////////////
    ///DCR
    const dcr_val = packed struct {
        ///DBA [0:4]
        ///DMA base address
        dba: u5 = 0,
        _unused5: u3 = 0,
        ///DBL [8:12]
        ///DMA burst length
        dbl: u5 = 0,
        _unused13: u19 = 0,
    };
    ///DMA control register
    pub const dcr = Register(dcr_val).init(0x40000000 + 0x48);

    //////////////////////////
    ///DMAR
    const dmar_val = packed struct {
        ///DMAB [0:15]
        ///DMA register for burst
        ///accesses
        dmab: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA address for full transfer
    pub const dmar = Register(dmar_val).init(0x40000000 + 0x4C);
};

///General purpose timer
pub const tim3 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        ///DIR [4:4]
        ///Direction
        dir: u1 = 0,
        ///CMS [5:6]
        ///Center-aligned mode
        ///selection
        cms: u2 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40000400 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u3 = 0,
        ///CCDS [3:3]
        ///Capture/compare DMA
        ///selection
        ccds: u1 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        ///TI1S [7:7]
        ///TI1 selection
        ti1s: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40000400 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        ///ETF [8:11]
        ///External trigger filter
        etf: u4 = 0,
        ///ETPS [12:13]
        ///External trigger prescaler
        etps: u2 = 0,
        ///ECE [14:14]
        ///External clock enable
        ece: u1 = 0,
        ///ETP [15:15]
        ///External trigger polarity
        etp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40000400 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        ///CC3IE [3:3]
        ///Capture/Compare 3 interrupt
        ///enable
        cc3ie: u1 = 0,
        ///CC4IE [4:4]
        ///Capture/Compare 4 interrupt
        ///enable
        cc4ie: u1 = 0,
        _unused5: u1 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        _unused7: u1 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        ///CC1DE [9:9]
        ///Capture/Compare 1 DMA request
        ///enable
        cc1de: u1 = 0,
        ///CC2DE [10:10]
        ///Capture/Compare 2 DMA request
        ///enable
        cc2de: u1 = 0,
        ///CC3DE [11:11]
        ///Capture/Compare 3 DMA request
        ///enable
        cc3de: u1 = 0,
        ///CC4DE [12:12]
        ///Capture/Compare 4 DMA request
        ///enable
        cc4de: u1 = 0,
        _unused13: u1 = 0,
        ///TDE [14:14]
        ///Trigger DMA request enable
        tde: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40000400 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        ///CC3IF [3:3]
        ///Capture/Compare 3 interrupt
        ///flag
        cc3if: u1 = 0,
        ///CC4IF [4:4]
        ///Capture/Compare 4 interrupt
        ///flag
        cc4if: u1 = 0,
        _unused5: u1 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        _unused7: u2 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        ///CC3OF [11:11]
        ///Capture/Compare 3 overcapture
        ///flag
        cc3of: u1 = 0,
        ///CC4OF [12:12]
        ///Capture/Compare 4 overcapture
        ///flag
        cc4of: u1 = 0,
        _unused13: u19 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40000400 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        ///CC3G [3:3]
        ///Capture/compare 3
        ///generation
        cc3g: u1 = 0,
        ///CC4G [4:4]
        ///Capture/compare 4
        ///generation
        cc4g: u1 = 0,
        _unused5: u1 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        _unused7: u25 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40000400 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output compare 1 mode
        oc1m: u3 = 0,
        ///OC1CE [7:7]
        ///Output compare 1 clear
        ///enable
        oc1ce: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output compare 2 mode
        oc2m: u3 = 0,
        ///OC2CE [15:15]
        ///Output compare 2 clear
        ///enable
        oc2ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40000400 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PSC [10:11]
        ///Input capture 2 prescaler
        ic2psc: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40000400 + 0x18);

    //////////////////////////
    ///CCMR2_Output
    const ccmr2_output_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///OC3FE [2:2]
        ///Output compare 3 fast
        ///enable
        oc3fe: u1 = 0,
        ///OC3PE [3:3]
        ///Output compare 3 preload
        ///enable
        oc3pe: u1 = 0,
        ///OC3M [4:6]
        ///Output compare 3 mode
        oc3m: u3 = 0,
        ///OC3CE [7:7]
        ///Output compare 3 clear
        ///enable
        oc3ce: u1 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///OC4FE [10:10]
        ///Output compare 4 fast
        ///enable
        oc4fe: u1 = 0,
        ///OC4PE [11:11]
        ///Output compare 4 preload
        ///enable
        oc4pe: u1 = 0,
        ///OC4M [12:14]
        ///Output compare 4 mode
        oc4m: u3 = 0,
        ///O24CE [15:15]
        ///Output compare 4 clear
        ///enable
        o24ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (output
    ///mode)
    pub const ccmr2_output = Register(ccmr2_output_val).init(0x40000400 + 0x1C);

    //////////////////////////
    ///CCMR2_Input
    const ccmr2_input_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///IC3PSC [2:3]
        ///Input capture 3 prescaler
        ic3psc: u2 = 0,
        ///IC3F [4:7]
        ///Input capture 3 filter
        ic3f: u4 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///IC4PSC [10:11]
        ///Input capture 4 prescaler
        ic4psc: u2 = 0,
        ///IC4F [12:15]
        ///Input capture 4 filter
        ic4f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (input
    ///mode)
    pub const ccmr2_input = Register(ccmr2_input_val).init(0x40000400 + 0x1C);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u2 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        _unused6: u2 = 0,
        ///CC3E [8:8]
        ///Capture/Compare 3 output
        ///enable
        cc3e: u1 = 0,
        ///CC3P [9:9]
        ///Capture/Compare 3 output
        ///Polarity
        cc3p: u1 = 0,
        _unused10: u2 = 0,
        ///CC4E [12:12]
        ///Capture/Compare 4 output
        ///enable
        cc4e: u1 = 0,
        ///CC4P [13:13]
        ///Capture/Compare 3 output
        ///Polarity
        cc4p: u1 = 0,
        _unused14: u18 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40000400 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40000400 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40000400 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40000400 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40000400 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40000400 + 0x38);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///CCR3 [0:15]
        ///Capture/Compare value
        ccr3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 3
    pub const ccr3 = Register(ccr3_val).init(0x40000400 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///CCR4 [0:15]
        ///Capture/Compare value
        ccr4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 4
    pub const ccr4 = Register(ccr4_val).init(0x40000400 + 0x40);

    //////////////////////////
    ///DCR
    const dcr_val = packed struct {
        ///DBA [0:4]
        ///DMA base address
        dba: u5 = 0,
        _unused5: u3 = 0,
        ///DBL [8:12]
        ///DMA burst length
        dbl: u5 = 0,
        _unused13: u19 = 0,
    };
    ///DMA control register
    pub const dcr = Register(dcr_val).init(0x40000400 + 0x48);

    //////////////////////////
    ///DMAR
    const dmar_val = packed struct {
        ///DMAB [0:15]
        ///DMA register for burst
        ///accesses
        dmab: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA address for full transfer
    pub const dmar = Register(dmar_val).init(0x40000400 + 0x4C);
};

///General purpose timer
pub const tim4 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        ///DIR [4:4]
        ///Direction
        dir: u1 = 0,
        ///CMS [5:6]
        ///Center-aligned mode
        ///selection
        cms: u2 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40000800 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u3 = 0,
        ///CCDS [3:3]
        ///Capture/compare DMA
        ///selection
        ccds: u1 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        ///TI1S [7:7]
        ///TI1 selection
        ti1s: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40000800 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        ///ETF [8:11]
        ///External trigger filter
        etf: u4 = 0,
        ///ETPS [12:13]
        ///External trigger prescaler
        etps: u2 = 0,
        ///ECE [14:14]
        ///External clock enable
        ece: u1 = 0,
        ///ETP [15:15]
        ///External trigger polarity
        etp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40000800 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        ///CC3IE [3:3]
        ///Capture/Compare 3 interrupt
        ///enable
        cc3ie: u1 = 0,
        ///CC4IE [4:4]
        ///Capture/Compare 4 interrupt
        ///enable
        cc4ie: u1 = 0,
        _unused5: u1 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        _unused7: u1 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        ///CC1DE [9:9]
        ///Capture/Compare 1 DMA request
        ///enable
        cc1de: u1 = 0,
        ///CC2DE [10:10]
        ///Capture/Compare 2 DMA request
        ///enable
        cc2de: u1 = 0,
        ///CC3DE [11:11]
        ///Capture/Compare 3 DMA request
        ///enable
        cc3de: u1 = 0,
        ///CC4DE [12:12]
        ///Capture/Compare 4 DMA request
        ///enable
        cc4de: u1 = 0,
        _unused13: u1 = 0,
        ///TDE [14:14]
        ///Trigger DMA request enable
        tde: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40000800 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        ///CC3IF [3:3]
        ///Capture/Compare 3 interrupt
        ///flag
        cc3if: u1 = 0,
        ///CC4IF [4:4]
        ///Capture/Compare 4 interrupt
        ///flag
        cc4if: u1 = 0,
        _unused5: u1 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        _unused7: u2 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        ///CC3OF [11:11]
        ///Capture/Compare 3 overcapture
        ///flag
        cc3of: u1 = 0,
        ///CC4OF [12:12]
        ///Capture/Compare 4 overcapture
        ///flag
        cc4of: u1 = 0,
        _unused13: u19 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40000800 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        ///CC3G [3:3]
        ///Capture/compare 3
        ///generation
        cc3g: u1 = 0,
        ///CC4G [4:4]
        ///Capture/compare 4
        ///generation
        cc4g: u1 = 0,
        _unused5: u1 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        _unused7: u25 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40000800 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output compare 1 mode
        oc1m: u3 = 0,
        ///OC1CE [7:7]
        ///Output compare 1 clear
        ///enable
        oc1ce: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output compare 2 mode
        oc2m: u3 = 0,
        ///OC2CE [15:15]
        ///Output compare 2 clear
        ///enable
        oc2ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40000800 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PSC [10:11]
        ///Input capture 2 prescaler
        ic2psc: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40000800 + 0x18);

    //////////////////////////
    ///CCMR2_Output
    const ccmr2_output_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///OC3FE [2:2]
        ///Output compare 3 fast
        ///enable
        oc3fe: u1 = 0,
        ///OC3PE [3:3]
        ///Output compare 3 preload
        ///enable
        oc3pe: u1 = 0,
        ///OC3M [4:6]
        ///Output compare 3 mode
        oc3m: u3 = 0,
        ///OC3CE [7:7]
        ///Output compare 3 clear
        ///enable
        oc3ce: u1 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///OC4FE [10:10]
        ///Output compare 4 fast
        ///enable
        oc4fe: u1 = 0,
        ///OC4PE [11:11]
        ///Output compare 4 preload
        ///enable
        oc4pe: u1 = 0,
        ///OC4M [12:14]
        ///Output compare 4 mode
        oc4m: u3 = 0,
        ///O24CE [15:15]
        ///Output compare 4 clear
        ///enable
        o24ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (output
    ///mode)
    pub const ccmr2_output = Register(ccmr2_output_val).init(0x40000800 + 0x1C);

    //////////////////////////
    ///CCMR2_Input
    const ccmr2_input_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///IC3PSC [2:3]
        ///Input capture 3 prescaler
        ic3psc: u2 = 0,
        ///IC3F [4:7]
        ///Input capture 3 filter
        ic3f: u4 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///IC4PSC [10:11]
        ///Input capture 4 prescaler
        ic4psc: u2 = 0,
        ///IC4F [12:15]
        ///Input capture 4 filter
        ic4f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (input
    ///mode)
    pub const ccmr2_input = Register(ccmr2_input_val).init(0x40000800 + 0x1C);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u2 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        _unused6: u2 = 0,
        ///CC3E [8:8]
        ///Capture/Compare 3 output
        ///enable
        cc3e: u1 = 0,
        ///CC3P [9:9]
        ///Capture/Compare 3 output
        ///Polarity
        cc3p: u1 = 0,
        _unused10: u2 = 0,
        ///CC4E [12:12]
        ///Capture/Compare 4 output
        ///enable
        cc4e: u1 = 0,
        ///CC4P [13:13]
        ///Capture/Compare 3 output
        ///Polarity
        cc4p: u1 = 0,
        _unused14: u18 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40000800 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40000800 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40000800 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40000800 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40000800 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40000800 + 0x38);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///CCR3 [0:15]
        ///Capture/Compare value
        ccr3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 3
    pub const ccr3 = Register(ccr3_val).init(0x40000800 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///CCR4 [0:15]
        ///Capture/Compare value
        ccr4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 4
    pub const ccr4 = Register(ccr4_val).init(0x40000800 + 0x40);

    //////////////////////////
    ///DCR
    const dcr_val = packed struct {
        ///DBA [0:4]
        ///DMA base address
        dba: u5 = 0,
        _unused5: u3 = 0,
        ///DBL [8:12]
        ///DMA burst length
        dbl: u5 = 0,
        _unused13: u19 = 0,
    };
    ///DMA control register
    pub const dcr = Register(dcr_val).init(0x40000800 + 0x48);

    //////////////////////////
    ///DMAR
    const dmar_val = packed struct {
        ///DMAB [0:15]
        ///DMA register for burst
        ///accesses
        dmab: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA address for full transfer
    pub const dmar = Register(dmar_val).init(0x40000800 + 0x4C);
};

///General purpose timer
pub const tim5 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        ///DIR [4:4]
        ///Direction
        dir: u1 = 0,
        ///CMS [5:6]
        ///Center-aligned mode
        ///selection
        cms: u2 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40000C00 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u3 = 0,
        ///CCDS [3:3]
        ///Capture/compare DMA
        ///selection
        ccds: u1 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        ///TI1S [7:7]
        ///TI1 selection
        ti1s: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40000C00 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        ///ETF [8:11]
        ///External trigger filter
        etf: u4 = 0,
        ///ETPS [12:13]
        ///External trigger prescaler
        etps: u2 = 0,
        ///ECE [14:14]
        ///External clock enable
        ece: u1 = 0,
        ///ETP [15:15]
        ///External trigger polarity
        etp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40000C00 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        ///CC3IE [3:3]
        ///Capture/Compare 3 interrupt
        ///enable
        cc3ie: u1 = 0,
        ///CC4IE [4:4]
        ///Capture/Compare 4 interrupt
        ///enable
        cc4ie: u1 = 0,
        _unused5: u1 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        _unused7: u1 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        ///CC1DE [9:9]
        ///Capture/Compare 1 DMA request
        ///enable
        cc1de: u1 = 0,
        ///CC2DE [10:10]
        ///Capture/Compare 2 DMA request
        ///enable
        cc2de: u1 = 0,
        ///CC3DE [11:11]
        ///Capture/Compare 3 DMA request
        ///enable
        cc3de: u1 = 0,
        ///CC4DE [12:12]
        ///Capture/Compare 4 DMA request
        ///enable
        cc4de: u1 = 0,
        _unused13: u1 = 0,
        ///TDE [14:14]
        ///Trigger DMA request enable
        tde: u1 = 0,
        _unused15: u17 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40000C00 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        ///CC3IF [3:3]
        ///Capture/Compare 3 interrupt
        ///flag
        cc3if: u1 = 0,
        ///CC4IF [4:4]
        ///Capture/Compare 4 interrupt
        ///flag
        cc4if: u1 = 0,
        _unused5: u1 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        _unused7: u2 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        ///CC3OF [11:11]
        ///Capture/Compare 3 overcapture
        ///flag
        cc3of: u1 = 0,
        ///CC4OF [12:12]
        ///Capture/Compare 4 overcapture
        ///flag
        cc4of: u1 = 0,
        _unused13: u19 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40000C00 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        ///CC3G [3:3]
        ///Capture/compare 3
        ///generation
        cc3g: u1 = 0,
        ///CC4G [4:4]
        ///Capture/compare 4
        ///generation
        cc4g: u1 = 0,
        _unused5: u1 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        _unused7: u25 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40000C00 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output compare 1 mode
        oc1m: u3 = 0,
        ///OC1CE [7:7]
        ///Output compare 1 clear
        ///enable
        oc1ce: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output compare 2 mode
        oc2m: u3 = 0,
        ///OC2CE [15:15]
        ///Output compare 2 clear
        ///enable
        oc2ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40000C00 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PSC [10:11]
        ///Input capture 2 prescaler
        ic2psc: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40000C00 + 0x18);

    //////////////////////////
    ///CCMR2_Output
    const ccmr2_output_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///OC3FE [2:2]
        ///Output compare 3 fast
        ///enable
        oc3fe: u1 = 0,
        ///OC3PE [3:3]
        ///Output compare 3 preload
        ///enable
        oc3pe: u1 = 0,
        ///OC3M [4:6]
        ///Output compare 3 mode
        oc3m: u3 = 0,
        ///OC3CE [7:7]
        ///Output compare 3 clear
        ///enable
        oc3ce: u1 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///OC4FE [10:10]
        ///Output compare 4 fast
        ///enable
        oc4fe: u1 = 0,
        ///OC4PE [11:11]
        ///Output compare 4 preload
        ///enable
        oc4pe: u1 = 0,
        ///OC4M [12:14]
        ///Output compare 4 mode
        oc4m: u3 = 0,
        ///O24CE [15:15]
        ///Output compare 4 clear
        ///enable
        o24ce: u1 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (output
    ///mode)
    pub const ccmr2_output = Register(ccmr2_output_val).init(0x40000C00 + 0x1C);

    //////////////////////////
    ///CCMR2_Input
    const ccmr2_input_val = packed struct {
        ///CC3S [0:1]
        ///Capture/Compare 3
        ///selection
        cc3s: u2 = 0,
        ///IC3PSC [2:3]
        ///Input capture 3 prescaler
        ic3psc: u2 = 0,
        ///IC3F [4:7]
        ///Input capture 3 filter
        ic3f: u4 = 0,
        ///CC4S [8:9]
        ///Capture/Compare 4
        ///selection
        cc4s: u2 = 0,
        ///IC4PSC [10:11]
        ///Input capture 4 prescaler
        ic4psc: u2 = 0,
        ///IC4F [12:15]
        ///Input capture 4 filter
        ic4f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 2 (input
    ///mode)
    pub const ccmr2_input = Register(ccmr2_input_val).init(0x40000C00 + 0x1C);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u2 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        _unused6: u2 = 0,
        ///CC3E [8:8]
        ///Capture/Compare 3 output
        ///enable
        cc3e: u1 = 0,
        ///CC3P [9:9]
        ///Capture/Compare 3 output
        ///Polarity
        cc3p: u1 = 0,
        _unused10: u2 = 0,
        ///CC4E [12:12]
        ///Capture/Compare 4 output
        ///enable
        cc4e: u1 = 0,
        ///CC4P [13:13]
        ///Capture/Compare 3 output
        ///Polarity
        cc4p: u1 = 0,
        _unused14: u18 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40000C00 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40000C00 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40000C00 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40000C00 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40000C00 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40000C00 + 0x38);

    //////////////////////////
    ///CCR3
    const ccr3_val = packed struct {
        ///CCR3 [0:15]
        ///Capture/Compare value
        ccr3: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 3
    pub const ccr3 = Register(ccr3_val).init(0x40000C00 + 0x3C);

    //////////////////////////
    ///CCR4
    const ccr4_val = packed struct {
        ///CCR4 [0:15]
        ///Capture/Compare value
        ccr4: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 4
    pub const ccr4 = Register(ccr4_val).init(0x40000C00 + 0x40);

    //////////////////////////
    ///DCR
    const dcr_val = packed struct {
        ///DBA [0:4]
        ///DMA base address
        dba: u5 = 0,
        _unused5: u3 = 0,
        ///DBL [8:12]
        ///DMA burst length
        dbl: u5 = 0,
        _unused13: u19 = 0,
    };
    ///DMA control register
    pub const dcr = Register(dcr_val).init(0x40000C00 + 0x48);

    //////////////////////////
    ///DMAR
    const dmar_val = packed struct {
        ///DMAB [0:15]
        ///DMA register for burst
        ///accesses
        dmab: u16 = 0,
        _unused16: u16 = 0,
    };
    ///DMA address for full transfer
    pub const dmar = Register(dmar_val).init(0x40000C00 + 0x4C);
};

///General purpose timer
pub const tim9 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        _unused4: u3 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40014C00 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40014C00 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        _unused8: u24 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40014C00 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        _unused3: u3 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        _unused7: u25 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40014C00 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        _unused3: u3 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        _unused7: u2 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        _unused11: u21 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40014C00 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        _unused3: u3 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        _unused7: u25 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40014C00 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output Compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        _unused7: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output Compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output Compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output Compare 2 mode
        oc2m: u3 = 0,
        _unused15: u17 = 0,
    };
    ///capture/compare mode register 1 (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40014C00 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PSC [10:11]
        ///Input capture 2 prescaler
        ic2psc: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40014C00 + 0x18);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        _unused6: u1 = 0,
        ///CC2NP [7:7]
        ///Capture/Compare 2 output
        ///Polarity
        cc2np: u1 = 0,
        _unused8: u24 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40014C00 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40014C00 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40014C00 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40014C00 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40014C00 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40014C00 + 0x38);
};

///General purpose timer
pub const tim12 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        _unused4: u3 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40001800 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40001800 + 0x4);

    //////////////////////////
    ///SMCR
    const smcr_val = packed struct {
        ///SMS [0:2]
        ///Slave mode selection
        sms: u3 = 0,
        _unused3: u1 = 0,
        ///TS [4:6]
        ///Trigger selection
        ts: u3 = 0,
        ///MSM [7:7]
        ///Master/Slave mode
        msm: u1 = 0,
        _unused8: u24 = 0,
    };
    ///slave mode control register
    pub const smcr = Register(smcr_val).init(0x40001800 + 0x8);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        ///CC2IE [2:2]
        ///Capture/Compare 2 interrupt
        ///enable
        cc2ie: u1 = 0,
        _unused3: u3 = 0,
        ///TIE [6:6]
        ///Trigger interrupt enable
        tie: u1 = 0,
        _unused7: u25 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40001800 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        ///CC2IF [2:2]
        ///Capture/Compare 2 interrupt
        ///flag
        cc2if: u1 = 0,
        _unused3: u3 = 0,
        ///TIF [6:6]
        ///Trigger interrupt flag
        tif: u1 = 0,
        _unused7: u2 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        ///CC2OF [10:10]
        ///Capture/compare 2 overcapture
        ///flag
        cc2of: u1 = 0,
        _unused11: u21 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40001800 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        ///CC2G [2:2]
        ///Capture/compare 2
        ///generation
        cc2g: u1 = 0,
        _unused3: u3 = 0,
        ///TG [6:6]
        ///Trigger generation
        tg: u1 = 0,
        _unused7: u25 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40001800 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///OC1FE [2:2]
        ///Output Compare 1 fast
        ///enable
        oc1fe: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        _unused7: u1 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///OC2FE [10:10]
        ///Output Compare 2 fast
        ///enable
        oc2fe: u1 = 0,
        ///OC2PE [11:11]
        ///Output Compare 2 preload
        ///enable
        oc2pe: u1 = 0,
        ///OC2M [12:14]
        ///Output Compare 2 mode
        oc2m: u3 = 0,
        _unused15: u17 = 0,
    };
    ///capture/compare mode register 1 (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40001800 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        ///CC2S [8:9]
        ///Capture/Compare 2
        ///selection
        cc2s: u2 = 0,
        ///IC2PSC [10:11]
        ///Input capture 2 prescaler
        ic2psc: u2 = 0,
        ///IC2F [12:15]
        ///Input capture 2 filter
        ic2f: u4 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare mode register 1 (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40001800 + 0x18);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        ///CC2E [4:4]
        ///Capture/Compare 2 output
        ///enable
        cc2e: u1 = 0,
        ///CC2P [5:5]
        ///Capture/Compare 2 output
        ///Polarity
        cc2p: u1 = 0,
        _unused6: u1 = 0,
        ///CC2NP [7:7]
        ///Capture/Compare 2 output
        ///Polarity
        cc2np: u1 = 0,
        _unused8: u24 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40001800 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40001800 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40001800 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40001800 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40001800 + 0x34);

    //////////////////////////
    ///CCR2
    const ccr2_val = packed struct {
        ///CCR2 [0:15]
        ///Capture/Compare 2 value
        ccr2: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 2
    pub const ccr2 = Register(ccr2_val).init(0x40001800 + 0x38);
};

///General purpose timer
pub const tim10 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        _unused3: u4 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40015000 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40015000 + 0x4);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        _unused2: u30 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40015000 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        _unused2: u7 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        _unused10: u22 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40015000 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        _unused2: u30 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40015000 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        _unused2: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        _unused7: u25 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40015000 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        _unused8: u24 = 0,
    };
    ///capture/compare mode register (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40015000 + 0x18);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        _unused4: u28 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40015000 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40015000 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40015000 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40015000 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40015000 + 0x34);
};

///General purpose timer
pub const tim11 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        _unused3: u4 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40015400 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40015400 + 0x4);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        _unused2: u30 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40015400 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        _unused2: u7 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        _unused10: u22 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40015400 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        _unused2: u30 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40015400 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        _unused2: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        _unused7: u25 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40015400 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        _unused8: u24 = 0,
    };
    ///capture/compare mode register (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40015400 + 0x18);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        _unused4: u28 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40015400 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40015400 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40015400 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40015400 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40015400 + 0x34);
};

///General purpose timer
pub const tim13 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        _unused3: u4 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40001C00 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40001C00 + 0x4);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        _unused2: u30 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40001C00 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        _unused2: u7 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        _unused10: u22 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40001C00 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        _unused2: u30 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40001C00 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        _unused2: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        _unused7: u25 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40001C00 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        _unused8: u24 = 0,
    };
    ///capture/compare mode register (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40001C00 + 0x18);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        _unused4: u28 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40001C00 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40001C00 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40001C00 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40001C00 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40001C00 + 0x34);
};

///General purpose timer
pub const tim14 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        _unused3: u4 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        ///CKD [8:9]
        ///Clock division
        ckd: u2 = 0,
        _unused10: u22 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40002000 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40002000 + 0x4);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        ///CC1IE [1:1]
        ///Capture/Compare 1 interrupt
        ///enable
        cc1ie: u1 = 0,
        _unused2: u30 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40002000 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        ///CC1IF [1:1]
        ///Capture/compare 1 interrupt
        ///flag
        cc1if: u1 = 0,
        _unused2: u7 = 0,
        ///CC1OF [9:9]
        ///Capture/Compare 1 overcapture
        ///flag
        cc1of: u1 = 0,
        _unused10: u22 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40002000 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        ///CC1G [1:1]
        ///Capture/compare 1
        ///generation
        cc1g: u1 = 0,
        _unused2: u30 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40002000 + 0x14);

    //////////////////////////
    ///CCMR1_Output
    const ccmr1_output_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        _unused2: u1 = 0,
        ///OC1PE [3:3]
        ///Output Compare 1 preload
        ///enable
        oc1pe: u1 = 0,
        ///OC1M [4:6]
        ///Output Compare 1 mode
        oc1m: u3 = 0,
        _unused7: u25 = 0,
    };
    ///capture/compare mode register (output
    ///mode)
    pub const ccmr1_output = Register(ccmr1_output_val).init(0x40002000 + 0x18);

    //////////////////////////
    ///CCMR1_Input
    const ccmr1_input_val = packed struct {
        ///CC1S [0:1]
        ///Capture/Compare 1
        ///selection
        cc1s: u2 = 0,
        ///IC1PSC [2:3]
        ///Input capture 1 prescaler
        ic1psc: u2 = 0,
        ///IC1F [4:7]
        ///Input capture 1 filter
        ic1f: u4 = 0,
        _unused8: u24 = 0,
    };
    ///capture/compare mode register (input
    ///mode)
    pub const ccmr1_input = Register(ccmr1_input_val).init(0x40002000 + 0x18);

    //////////////////////////
    ///CCER
    const ccer_val = packed struct {
        ///CC1E [0:0]
        ///Capture/Compare 1 output
        ///enable
        cc1e: u1 = 0,
        ///CC1P [1:1]
        ///Capture/Compare 1 output
        ///Polarity
        cc1p: u1 = 0,
        _unused2: u1 = 0,
        ///CC1NP [3:3]
        ///Capture/Compare 1 output
        ///Polarity
        cc1np: u1 = 0,
        _unused4: u28 = 0,
    };
    ///capture/compare enable
    ///register
    pub const ccer = Register(ccer_val).init(0x40002000 + 0x20);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40002000 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40002000 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40002000 + 0x2C);

    //////////////////////////
    ///CCR1
    const ccr1_val = packed struct {
        ///CCR1 [0:15]
        ///Capture/Compare 1 value
        ccr1: u16 = 0,
        _unused16: u16 = 0,
    };
    ///capture/compare register 1
    pub const ccr1 = Register(ccr1_val).init(0x40002000 + 0x34);
};

///Basic timer
pub const tim6 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        _unused4: u3 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40001000 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40001000 + 0x4);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        _unused1: u7 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        _unused9: u23 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40001000 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        _unused1: u31 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40001000 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        _unused1: u31 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40001000 + 0x14);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///Low counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40001000 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40001000 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Low Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40001000 + 0x2C);
};

///Basic timer
pub const tim7 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CEN [0:0]
        ///Counter enable
        cen: u1 = 0,
        ///UDIS [1:1]
        ///Update disable
        udis: u1 = 0,
        ///URS [2:2]
        ///Update request source
        urs: u1 = 0,
        ///OPM [3:3]
        ///One-pulse mode
        opm: u1 = 0,
        _unused4: u3 = 0,
        ///ARPE [7:7]
        ///Auto-reload preload enable
        arpe: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40001400 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        _unused0: u4 = 0,
        ///MMS [4:6]
        ///Master mode selection
        mms: u3 = 0,
        _unused7: u25 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40001400 + 0x4);

    //////////////////////////
    ///DIER
    const dier_val = packed struct {
        ///UIE [0:0]
        ///Update interrupt enable
        uie: u1 = 0,
        _unused1: u7 = 0,
        ///UDE [8:8]
        ///Update DMA request enable
        ude: u1 = 0,
        _unused9: u23 = 0,
    };
    ///DMA/Interrupt enable register
    pub const dier = Register(dier_val).init(0x40001400 + 0xC);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///UIF [0:0]
        ///Update interrupt flag
        uif: u1 = 0,
        _unused1: u31 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40001400 + 0x10);

    //////////////////////////
    ///EGR
    const egr_val = packed struct {
        ///UG [0:0]
        ///Update generation
        ug: u1 = 0,
        _unused1: u31 = 0,
    };
    ///event generation register
    pub const egr = RegisterRW(void, egr_val).init(0x40001400 + 0x14);

    //////////////////////////
    ///CNT
    const cnt_val = packed struct {
        ///CNT [0:15]
        ///Low counter value
        cnt: u16 = 0,
        _unused16: u16 = 0,
    };
    ///counter
    pub const cnt = Register(cnt_val).init(0x40001400 + 0x24);

    //////////////////////////
    ///PSC
    const psc_val = packed struct {
        ///PSC [0:15]
        ///Prescaler value
        psc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///prescaler
    pub const psc = Register(psc_val).init(0x40001400 + 0x28);

    //////////////////////////
    ///ARR
    const arr_val = packed struct {
        ///ARR [0:15]
        ///Low Auto-reload value
        arr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///auto-reload register
    pub const arr = Register(arr_val).init(0x40001400 + 0x2C);
};

///Inter integrated circuit
pub const i2c1 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///PE [0:0]
        ///Peripheral enable
        pe: u1 = 0,
        ///SMBUS [1:1]
        ///SMBus mode
        smbus: u1 = 0,
        _unused2: u1 = 0,
        ///SMBTYPE [3:3]
        ///SMBus type
        smbtype: u1 = 0,
        ///ENARP [4:4]
        ///ARP enable
        enarp: u1 = 0,
        ///ENPEC [5:5]
        ///PEC enable
        enpec: u1 = 0,
        ///ENGC [6:6]
        ///General call enable
        engc: u1 = 0,
        ///NOSTRETCH [7:7]
        ///Clock stretching disable (Slave
        ///mode)
        nostretch: u1 = 0,
        ///START [8:8]
        ///Start generation
        start: u1 = 0,
        ///STOP [9:9]
        ///Stop generation
        stop: u1 = 0,
        ///ACK [10:10]
        ///Acknowledge enable
        ack: u1 = 0,
        ///POS [11:11]
        ///Acknowledge/PEC Position (for data
        ///reception)
        pos: u1 = 0,
        ///PEC [12:12]
        ///Packet error checking
        pec: u1 = 0,
        ///ALERT [13:13]
        ///SMBus alert
        alert: u1 = 0,
        _unused14: u1 = 0,
        ///SWRST [15:15]
        ///Software reset
        swrst: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Control register 1
    pub const cr1 = Register(cr1_val).init(0x40005400 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///FREQ [0:5]
        ///Peripheral clock frequency
        freq: u6 = 0,
        _unused6: u2 = 0,
        ///ITERREN [8:8]
        ///Error interrupt enable
        iterren: u1 = 0,
        ///ITEVTEN [9:9]
        ///Event interrupt enable
        itevten: u1 = 0,
        ///ITBUFEN [10:10]
        ///Buffer interrupt enable
        itbufen: u1 = 0,
        ///DMAEN [11:11]
        ///DMA requests enable
        dmaen: u1 = 0,
        ///LAST [12:12]
        ///DMA last transfer
        last: u1 = 0,
        _unused13: u19 = 0,
    };
    ///Control register 2
    pub const cr2 = Register(cr2_val).init(0x40005400 + 0x4);

    //////////////////////////
    ///OAR1
    const oar1_val = packed struct {
        ///ADD0 [0:0]
        ///Interface address
        add0: u1 = 0,
        ///ADD7 [1:7]
        ///Interface address
        add7: u7 = 0,
        ///ADD10 [8:9]
        ///Interface address
        add10: u2 = 0,
        _unused10: u5 = 0,
        ///ADDMODE [15:15]
        ///Addressing mode (slave
        ///mode)
        addmode: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Own address register 1
    pub const oar1 = Register(oar1_val).init(0x40005400 + 0x8);

    //////////////////////////
    ///OAR2
    const oar2_val = packed struct {
        ///ENDUAL [0:0]
        ///Dual addressing mode
        ///enable
        endual: u1 = 0,
        ///ADD2 [1:7]
        ///Interface address
        add2: u7 = 0,
        _unused8: u24 = 0,
    };
    ///Own address register 2
    pub const oar2 = Register(oar2_val).init(0x40005400 + 0xC);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:7]
        ///8-bit data register
        dr: u8 = 0,
        _unused8: u24 = 0,
    };
    ///Data register
    pub const dr = Register(dr_val).init(0x40005400 + 0x10);

    //////////////////////////
    ///SR1
    const sr1_val = packed struct {
        ///SB [0:0]
        ///Start bit (Master mode)
        sb: u1 = 0,
        ///ADDR [1:1]
        ///Address sent (master mode)/matched
        ///(slave mode)
        addr: u1 = 0,
        ///BTF [2:2]
        ///Byte transfer finished
        btf: u1 = 0,
        ///ADD10 [3:3]
        ///10-bit header sent (Master
        ///mode)
        add10: u1 = 0,
        ///STOPF [4:4]
        ///Stop detection (slave
        ///mode)
        stopf: u1 = 0,
        _unused5: u1 = 0,
        ///RxNE [6:6]
        ///Data register not empty
        ///(receivers)
        rx_ne: u1 = 0,
        ///TxE [7:7]
        ///Data register empty
        ///(transmitters)
        tx_e: u1 = 0,
        ///BERR [8:8]
        ///Bus error
        berr: u1 = 0,
        ///ARLO [9:9]
        ///Arbitration lost (master
        ///mode)
        arlo: u1 = 0,
        ///AF [10:10]
        ///Acknowledge failure
        af: u1 = 0,
        ///OVR [11:11]
        ///Overrun/Underrun
        ovr: u1 = 0,
        ///PECERR [12:12]
        ///PEC Error in reception
        pecerr: u1 = 0,
        _unused13: u1 = 0,
        ///TIMEOUT [14:14]
        ///Timeout or Tlow error
        timeout: u1 = 0,
        ///SMBALERT [15:15]
        ///SMBus alert
        smbalert: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Status register 1
    pub const sr1 = Register(sr1_val).init(0x40005400 + 0x14);

    //////////////////////////
    ///SR2
    const sr2_val = packed struct {
        ///MSL [0:0]
        ///Master/slave
        msl: u1 = 0,
        ///BUSY [1:1]
        ///Bus busy
        busy: u1 = 0,
        ///TRA [2:2]
        ///Transmitter/receiver
        tra: u1 = 0,
        _unused3: u1 = 0,
        ///GENCALL [4:4]
        ///General call address (Slave
        ///mode)
        gencall: u1 = 0,
        ///SMBDEFAULT [5:5]
        ///SMBus device default address (Slave
        ///mode)
        smbdefault: u1 = 0,
        ///SMBHOST [6:6]
        ///SMBus host header (Slave
        ///mode)
        smbhost: u1 = 0,
        ///DUALF [7:7]
        ///Dual flag (Slave mode)
        dualf: u1 = 0,
        ///PEC [8:15]
        ///acket error checking
        ///register
        pec: u8 = 0,
        _unused16: u16 = 0,
    };
    ///Status register 2
    pub const sr2 = RegisterRW(sr2_val, void).init(0x40005400 + 0x18);

    //////////////////////////
    ///CCR
    const ccr_val = packed struct {
        ///CCR [0:11]
        ///Clock control register in Fast/Standard
        ///mode (Master mode)
        ccr: u12 = 0,
        _unused12: u2 = 0,
        ///DUTY [14:14]
        ///Fast mode duty cycle
        duty: u1 = 0,
        ///F_S [15:15]
        ///I2C master mode selection
        f_s: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Clock control register
    pub const ccr = Register(ccr_val).init(0x40005400 + 0x1C);

    //////////////////////////
    ///TRISE
    const trise_val = packed struct {
        ///TRISE [0:5]
        ///Maximum rise time in Fast/Standard mode
        ///(Master mode)
        trise: u6 = 2,
        _unused6: u26 = 0,
    };
    ///TRISE register
    pub const trise = Register(trise_val).init(0x40005400 + 0x20);
};

///Inter integrated circuit
pub const i2c2 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///PE [0:0]
        ///Peripheral enable
        pe: u1 = 0,
        ///SMBUS [1:1]
        ///SMBus mode
        smbus: u1 = 0,
        _unused2: u1 = 0,
        ///SMBTYPE [3:3]
        ///SMBus type
        smbtype: u1 = 0,
        ///ENARP [4:4]
        ///ARP enable
        enarp: u1 = 0,
        ///ENPEC [5:5]
        ///PEC enable
        enpec: u1 = 0,
        ///ENGC [6:6]
        ///General call enable
        engc: u1 = 0,
        ///NOSTRETCH [7:7]
        ///Clock stretching disable (Slave
        ///mode)
        nostretch: u1 = 0,
        ///START [8:8]
        ///Start generation
        start: u1 = 0,
        ///STOP [9:9]
        ///Stop generation
        stop: u1 = 0,
        ///ACK [10:10]
        ///Acknowledge enable
        ack: u1 = 0,
        ///POS [11:11]
        ///Acknowledge/PEC Position (for data
        ///reception)
        pos: u1 = 0,
        ///PEC [12:12]
        ///Packet error checking
        pec: u1 = 0,
        ///ALERT [13:13]
        ///SMBus alert
        alert: u1 = 0,
        _unused14: u1 = 0,
        ///SWRST [15:15]
        ///Software reset
        swrst: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Control register 1
    pub const cr1 = Register(cr1_val).init(0x40005800 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///FREQ [0:5]
        ///Peripheral clock frequency
        freq: u6 = 0,
        _unused6: u2 = 0,
        ///ITERREN [8:8]
        ///Error interrupt enable
        iterren: u1 = 0,
        ///ITEVTEN [9:9]
        ///Event interrupt enable
        itevten: u1 = 0,
        ///ITBUFEN [10:10]
        ///Buffer interrupt enable
        itbufen: u1 = 0,
        ///DMAEN [11:11]
        ///DMA requests enable
        dmaen: u1 = 0,
        ///LAST [12:12]
        ///DMA last transfer
        last: u1 = 0,
        _unused13: u19 = 0,
    };
    ///Control register 2
    pub const cr2 = Register(cr2_val).init(0x40005800 + 0x4);

    //////////////////////////
    ///OAR1
    const oar1_val = packed struct {
        ///ADD0 [0:0]
        ///Interface address
        add0: u1 = 0,
        ///ADD7 [1:7]
        ///Interface address
        add7: u7 = 0,
        ///ADD10 [8:9]
        ///Interface address
        add10: u2 = 0,
        _unused10: u5 = 0,
        ///ADDMODE [15:15]
        ///Addressing mode (slave
        ///mode)
        addmode: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Own address register 1
    pub const oar1 = Register(oar1_val).init(0x40005800 + 0x8);

    //////////////////////////
    ///OAR2
    const oar2_val = packed struct {
        ///ENDUAL [0:0]
        ///Dual addressing mode
        ///enable
        endual: u1 = 0,
        ///ADD2 [1:7]
        ///Interface address
        add2: u7 = 0,
        _unused8: u24 = 0,
    };
    ///Own address register 2
    pub const oar2 = Register(oar2_val).init(0x40005800 + 0xC);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:7]
        ///8-bit data register
        dr: u8 = 0,
        _unused8: u24 = 0,
    };
    ///Data register
    pub const dr = Register(dr_val).init(0x40005800 + 0x10);

    //////////////////////////
    ///SR1
    const sr1_val = packed struct {
        ///SB [0:0]
        ///Start bit (Master mode)
        sb: u1 = 0,
        ///ADDR [1:1]
        ///Address sent (master mode)/matched
        ///(slave mode)
        addr: u1 = 0,
        ///BTF [2:2]
        ///Byte transfer finished
        btf: u1 = 0,
        ///ADD10 [3:3]
        ///10-bit header sent (Master
        ///mode)
        add10: u1 = 0,
        ///STOPF [4:4]
        ///Stop detection (slave
        ///mode)
        stopf: u1 = 0,
        _unused5: u1 = 0,
        ///RxNE [6:6]
        ///Data register not empty
        ///(receivers)
        rx_ne: u1 = 0,
        ///TxE [7:7]
        ///Data register empty
        ///(transmitters)
        tx_e: u1 = 0,
        ///BERR [8:8]
        ///Bus error
        berr: u1 = 0,
        ///ARLO [9:9]
        ///Arbitration lost (master
        ///mode)
        arlo: u1 = 0,
        ///AF [10:10]
        ///Acknowledge failure
        af: u1 = 0,
        ///OVR [11:11]
        ///Overrun/Underrun
        ovr: u1 = 0,
        ///PECERR [12:12]
        ///PEC Error in reception
        pecerr: u1 = 0,
        _unused13: u1 = 0,
        ///TIMEOUT [14:14]
        ///Timeout or Tlow error
        timeout: u1 = 0,
        ///SMBALERT [15:15]
        ///SMBus alert
        smbalert: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Status register 1
    pub const sr1 = Register(sr1_val).init(0x40005800 + 0x14);

    //////////////////////////
    ///SR2
    const sr2_val = packed struct {
        ///MSL [0:0]
        ///Master/slave
        msl: u1 = 0,
        ///BUSY [1:1]
        ///Bus busy
        busy: u1 = 0,
        ///TRA [2:2]
        ///Transmitter/receiver
        tra: u1 = 0,
        _unused3: u1 = 0,
        ///GENCALL [4:4]
        ///General call address (Slave
        ///mode)
        gencall: u1 = 0,
        ///SMBDEFAULT [5:5]
        ///SMBus device default address (Slave
        ///mode)
        smbdefault: u1 = 0,
        ///SMBHOST [6:6]
        ///SMBus host header (Slave
        ///mode)
        smbhost: u1 = 0,
        ///DUALF [7:7]
        ///Dual flag (Slave mode)
        dualf: u1 = 0,
        ///PEC [8:15]
        ///acket error checking
        ///register
        pec: u8 = 0,
        _unused16: u16 = 0,
    };
    ///Status register 2
    pub const sr2 = RegisterRW(sr2_val, void).init(0x40005800 + 0x18);

    //////////////////////////
    ///CCR
    const ccr_val = packed struct {
        ///CCR [0:11]
        ///Clock control register in Fast/Standard
        ///mode (Master mode)
        ccr: u12 = 0,
        _unused12: u2 = 0,
        ///DUTY [14:14]
        ///Fast mode duty cycle
        duty: u1 = 0,
        ///F_S [15:15]
        ///I2C master mode selection
        f_s: u1 = 0,
        _unused16: u16 = 0,
    };
    ///Clock control register
    pub const ccr = Register(ccr_val).init(0x40005800 + 0x1C);

    //////////////////////////
    ///TRISE
    const trise_val = packed struct {
        ///TRISE [0:5]
        ///Maximum rise time in Fast/Standard mode
        ///(Master mode)
        trise: u6 = 2,
        _unused6: u26 = 0,
    };
    ///TRISE register
    pub const trise = Register(trise_val).init(0x40005800 + 0x20);
};

///Serial peripheral interface
pub const spi1 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CPHA [0:0]
        ///Clock phase
        cpha: u1 = 0,
        ///CPOL [1:1]
        ///Clock polarity
        cpol: u1 = 0,
        ///MSTR [2:2]
        ///Master selection
        mstr: u1 = 0,
        ///BR [3:5]
        ///Baud rate control
        br: u3 = 0,
        ///SPE [6:6]
        ///SPI enable
        spe: u1 = 0,
        ///LSBFIRST [7:7]
        ///Frame format
        lsbfirst: u1 = 0,
        ///SSI [8:8]
        ///Internal slave select
        ssi: u1 = 0,
        ///SSM [9:9]
        ///Software slave management
        ssm: u1 = 0,
        ///RXONLY [10:10]
        ///Receive only
        rxonly: u1 = 0,
        ///DFF [11:11]
        ///Data frame format
        dff: u1 = 0,
        ///CRCNEXT [12:12]
        ///CRC transfer next
        crcnext: u1 = 0,
        ///CRCEN [13:13]
        ///Hardware CRC calculation
        ///enable
        crcen: u1 = 0,
        ///BIDIOE [14:14]
        ///Output enable in bidirectional
        ///mode
        bidioe: u1 = 0,
        ///BIDIMODE [15:15]
        ///Bidirectional data mode
        ///enable
        bidimode: u1 = 0,
        _unused16: u16 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40013000 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///RXDMAEN [0:0]
        ///Rx buffer DMA enable
        rxdmaen: u1 = 0,
        ///TXDMAEN [1:1]
        ///Tx buffer DMA enable
        txdmaen: u1 = 0,
        ///SSOE [2:2]
        ///SS output enable
        ssoe: u1 = 0,
        _unused3: u2 = 0,
        ///ERRIE [5:5]
        ///Error interrupt enable
        errie: u1 = 0,
        ///RXNEIE [6:6]
        ///RX buffer not empty interrupt
        ///enable
        rxneie: u1 = 0,
        ///TXEIE [7:7]
        ///Tx buffer empty interrupt
        ///enable
        txeie: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40013000 + 0x4);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///RXNE [0:0]
        ///Receive buffer not empty
        rxne: u1 = 0,
        ///TXE [1:1]
        ///Transmit buffer empty
        txe: u1 = 1,
        ///CHSIDE [2:2]
        ///Channel side
        chside: u1 = 0,
        ///UDR [3:3]
        ///Underrun flag
        udr: u1 = 0,
        ///CRCERR [4:4]
        ///CRC error flag
        crcerr: u1 = 0,
        ///MODF [5:5]
        ///Mode fault
        modf: u1 = 0,
        ///OVR [6:6]
        ///Overrun flag
        ovr: u1 = 0,
        ///BSY [7:7]
        ///Busy flag
        bsy: u1 = 0,
        _unused8: u24 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40013000 + 0x8);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:15]
        ///Data register
        dr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///data register
    pub const dr = Register(dr_val).init(0x40013000 + 0xC);

    //////////////////////////
    ///CRCPR
    const crcpr_val = packed struct {
        ///CRCPOLY [0:15]
        ///CRC polynomial register
        crcpoly: u16 = 7,
        _unused16: u16 = 0,
    };
    ///CRC polynomial register
    pub const crcpr = Register(crcpr_val).init(0x40013000 + 0x10);

    //////////////////////////
    ///RXCRCR
    const rxcrcr_val = packed struct {
        ///RxCRC [0:15]
        ///Rx CRC register
        rx_crc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///RX CRC register
    pub const rxcrcr = RegisterRW(rxcrcr_val, void).init(0x40013000 + 0x14);

    //////////////////////////
    ///TXCRCR
    const txcrcr_val = packed struct {
        ///TxCRC [0:15]
        ///Tx CRC register
        tx_crc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///TX CRC register
    pub const txcrcr = RegisterRW(txcrcr_val, void).init(0x40013000 + 0x18);

    //////////////////////////
    ///I2SCFGR
    const i2scfgr_val = packed struct {
        ///CHLEN [0:0]
        ///Channel length (number of bits per audio
        ///channel)
        chlen: u1 = 0,
        ///DATLEN [1:2]
        ///Data length to be
        ///transferred
        datlen: u2 = 0,
        ///CKPOL [3:3]
        ///Steady state clock
        ///polarity
        ckpol: u1 = 0,
        ///I2SSTD [4:5]
        ///I2S standard selection
        i2sstd: u2 = 0,
        _unused6: u1 = 0,
        ///PCMSYNC [7:7]
        ///PCM frame synchronization
        pcmsync: u1 = 0,
        ///I2SCFG [8:9]
        ///I2S configuration mode
        i2scfg: u2 = 0,
        ///I2SE [10:10]
        ///I2S Enable
        i2se: u1 = 0,
        ///I2SMOD [11:11]
        ///I2S mode selection
        i2smod: u1 = 0,
        _unused12: u20 = 0,
    };
    ///I2S configuration register
    pub const i2scfgr = Register(i2scfgr_val).init(0x40013000 + 0x1C);

    //////////////////////////
    ///I2SPR
    const i2spr_val = packed struct {
        ///I2SDIV [0:7]
        ///I2S Linear prescaler
        i2sdiv: u8 = 16,
        ///ODD [8:8]
        ///Odd factor for the
        ///prescaler
        odd: u1 = 0,
        ///MCKOE [9:9]
        ///Master clock output enable
        mckoe: u1 = 0,
        _unused10: u22 = 0,
    };
    ///I2S prescaler register
    pub const i2spr = Register(i2spr_val).init(0x40013000 + 0x20);
};

///Serial peripheral interface
pub const spi2 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CPHA [0:0]
        ///Clock phase
        cpha: u1 = 0,
        ///CPOL [1:1]
        ///Clock polarity
        cpol: u1 = 0,
        ///MSTR [2:2]
        ///Master selection
        mstr: u1 = 0,
        ///BR [3:5]
        ///Baud rate control
        br: u3 = 0,
        ///SPE [6:6]
        ///SPI enable
        spe: u1 = 0,
        ///LSBFIRST [7:7]
        ///Frame format
        lsbfirst: u1 = 0,
        ///SSI [8:8]
        ///Internal slave select
        ssi: u1 = 0,
        ///SSM [9:9]
        ///Software slave management
        ssm: u1 = 0,
        ///RXONLY [10:10]
        ///Receive only
        rxonly: u1 = 0,
        ///DFF [11:11]
        ///Data frame format
        dff: u1 = 0,
        ///CRCNEXT [12:12]
        ///CRC transfer next
        crcnext: u1 = 0,
        ///CRCEN [13:13]
        ///Hardware CRC calculation
        ///enable
        crcen: u1 = 0,
        ///BIDIOE [14:14]
        ///Output enable in bidirectional
        ///mode
        bidioe: u1 = 0,
        ///BIDIMODE [15:15]
        ///Bidirectional data mode
        ///enable
        bidimode: u1 = 0,
        _unused16: u16 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40003800 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///RXDMAEN [0:0]
        ///Rx buffer DMA enable
        rxdmaen: u1 = 0,
        ///TXDMAEN [1:1]
        ///Tx buffer DMA enable
        txdmaen: u1 = 0,
        ///SSOE [2:2]
        ///SS output enable
        ssoe: u1 = 0,
        _unused3: u2 = 0,
        ///ERRIE [5:5]
        ///Error interrupt enable
        errie: u1 = 0,
        ///RXNEIE [6:6]
        ///RX buffer not empty interrupt
        ///enable
        rxneie: u1 = 0,
        ///TXEIE [7:7]
        ///Tx buffer empty interrupt
        ///enable
        txeie: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40003800 + 0x4);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///RXNE [0:0]
        ///Receive buffer not empty
        rxne: u1 = 0,
        ///TXE [1:1]
        ///Transmit buffer empty
        txe: u1 = 1,
        ///CHSIDE [2:2]
        ///Channel side
        chside: u1 = 0,
        ///UDR [3:3]
        ///Underrun flag
        udr: u1 = 0,
        ///CRCERR [4:4]
        ///CRC error flag
        crcerr: u1 = 0,
        ///MODF [5:5]
        ///Mode fault
        modf: u1 = 0,
        ///OVR [6:6]
        ///Overrun flag
        ovr: u1 = 0,
        ///BSY [7:7]
        ///Busy flag
        bsy: u1 = 0,
        _unused8: u24 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40003800 + 0x8);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:15]
        ///Data register
        dr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///data register
    pub const dr = Register(dr_val).init(0x40003800 + 0xC);

    //////////////////////////
    ///CRCPR
    const crcpr_val = packed struct {
        ///CRCPOLY [0:15]
        ///CRC polynomial register
        crcpoly: u16 = 7,
        _unused16: u16 = 0,
    };
    ///CRC polynomial register
    pub const crcpr = Register(crcpr_val).init(0x40003800 + 0x10);

    //////////////////////////
    ///RXCRCR
    const rxcrcr_val = packed struct {
        ///RxCRC [0:15]
        ///Rx CRC register
        rx_crc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///RX CRC register
    pub const rxcrcr = RegisterRW(rxcrcr_val, void).init(0x40003800 + 0x14);

    //////////////////////////
    ///TXCRCR
    const txcrcr_val = packed struct {
        ///TxCRC [0:15]
        ///Tx CRC register
        tx_crc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///TX CRC register
    pub const txcrcr = RegisterRW(txcrcr_val, void).init(0x40003800 + 0x18);

    //////////////////////////
    ///I2SCFGR
    const i2scfgr_val = packed struct {
        ///CHLEN [0:0]
        ///Channel length (number of bits per audio
        ///channel)
        chlen: u1 = 0,
        ///DATLEN [1:2]
        ///Data length to be
        ///transferred
        datlen: u2 = 0,
        ///CKPOL [3:3]
        ///Steady state clock
        ///polarity
        ckpol: u1 = 0,
        ///I2SSTD [4:5]
        ///I2S standard selection
        i2sstd: u2 = 0,
        _unused6: u1 = 0,
        ///PCMSYNC [7:7]
        ///PCM frame synchronization
        pcmsync: u1 = 0,
        ///I2SCFG [8:9]
        ///I2S configuration mode
        i2scfg: u2 = 0,
        ///I2SE [10:10]
        ///I2S Enable
        i2se: u1 = 0,
        ///I2SMOD [11:11]
        ///I2S mode selection
        i2smod: u1 = 0,
        _unused12: u20 = 0,
    };
    ///I2S configuration register
    pub const i2scfgr = Register(i2scfgr_val).init(0x40003800 + 0x1C);

    //////////////////////////
    ///I2SPR
    const i2spr_val = packed struct {
        ///I2SDIV [0:7]
        ///I2S Linear prescaler
        i2sdiv: u8 = 16,
        ///ODD [8:8]
        ///Odd factor for the
        ///prescaler
        odd: u1 = 0,
        ///MCKOE [9:9]
        ///Master clock output enable
        mckoe: u1 = 0,
        _unused10: u22 = 0,
    };
    ///I2S prescaler register
    pub const i2spr = Register(i2spr_val).init(0x40003800 + 0x20);
};

///Serial peripheral interface
pub const spi3 = struct {

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///CPHA [0:0]
        ///Clock phase
        cpha: u1 = 0,
        ///CPOL [1:1]
        ///Clock polarity
        cpol: u1 = 0,
        ///MSTR [2:2]
        ///Master selection
        mstr: u1 = 0,
        ///BR [3:5]
        ///Baud rate control
        br: u3 = 0,
        ///SPE [6:6]
        ///SPI enable
        spe: u1 = 0,
        ///LSBFIRST [7:7]
        ///Frame format
        lsbfirst: u1 = 0,
        ///SSI [8:8]
        ///Internal slave select
        ssi: u1 = 0,
        ///SSM [9:9]
        ///Software slave management
        ssm: u1 = 0,
        ///RXONLY [10:10]
        ///Receive only
        rxonly: u1 = 0,
        ///DFF [11:11]
        ///Data frame format
        dff: u1 = 0,
        ///CRCNEXT [12:12]
        ///CRC transfer next
        crcnext: u1 = 0,
        ///CRCEN [13:13]
        ///Hardware CRC calculation
        ///enable
        crcen: u1 = 0,
        ///BIDIOE [14:14]
        ///Output enable in bidirectional
        ///mode
        bidioe: u1 = 0,
        ///BIDIMODE [15:15]
        ///Bidirectional data mode
        ///enable
        bidimode: u1 = 0,
        _unused16: u16 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40003C00 + 0x0);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///RXDMAEN [0:0]
        ///Rx buffer DMA enable
        rxdmaen: u1 = 0,
        ///TXDMAEN [1:1]
        ///Tx buffer DMA enable
        txdmaen: u1 = 0,
        ///SSOE [2:2]
        ///SS output enable
        ssoe: u1 = 0,
        _unused3: u2 = 0,
        ///ERRIE [5:5]
        ///Error interrupt enable
        errie: u1 = 0,
        ///RXNEIE [6:6]
        ///RX buffer not empty interrupt
        ///enable
        rxneie: u1 = 0,
        ///TXEIE [7:7]
        ///Tx buffer empty interrupt
        ///enable
        txeie: u1 = 0,
        _unused8: u24 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40003C00 + 0x4);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///RXNE [0:0]
        ///Receive buffer not empty
        rxne: u1 = 0,
        ///TXE [1:1]
        ///Transmit buffer empty
        txe: u1 = 1,
        ///CHSIDE [2:2]
        ///Channel side
        chside: u1 = 0,
        ///UDR [3:3]
        ///Underrun flag
        udr: u1 = 0,
        ///CRCERR [4:4]
        ///CRC error flag
        crcerr: u1 = 0,
        ///MODF [5:5]
        ///Mode fault
        modf: u1 = 0,
        ///OVR [6:6]
        ///Overrun flag
        ovr: u1 = 0,
        ///BSY [7:7]
        ///Busy flag
        bsy: u1 = 0,
        _unused8: u24 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40003C00 + 0x8);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:15]
        ///Data register
        dr: u16 = 0,
        _unused16: u16 = 0,
    };
    ///data register
    pub const dr = Register(dr_val).init(0x40003C00 + 0xC);

    //////////////////////////
    ///CRCPR
    const crcpr_val = packed struct {
        ///CRCPOLY [0:15]
        ///CRC polynomial register
        crcpoly: u16 = 7,
        _unused16: u16 = 0,
    };
    ///CRC polynomial register
    pub const crcpr = Register(crcpr_val).init(0x40003C00 + 0x10);

    //////////////////////////
    ///RXCRCR
    const rxcrcr_val = packed struct {
        ///RxCRC [0:15]
        ///Rx CRC register
        rx_crc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///RX CRC register
    pub const rxcrcr = RegisterRW(rxcrcr_val, void).init(0x40003C00 + 0x14);

    //////////////////////////
    ///TXCRCR
    const txcrcr_val = packed struct {
        ///TxCRC [0:15]
        ///Tx CRC register
        tx_crc: u16 = 0,
        _unused16: u16 = 0,
    };
    ///TX CRC register
    pub const txcrcr = RegisterRW(txcrcr_val, void).init(0x40003C00 + 0x18);

    //////////////////////////
    ///I2SCFGR
    const i2scfgr_val = packed struct {
        ///CHLEN [0:0]
        ///Channel length (number of bits per audio
        ///channel)
        chlen: u1 = 0,
        ///DATLEN [1:2]
        ///Data length to be
        ///transferred
        datlen: u2 = 0,
        ///CKPOL [3:3]
        ///Steady state clock
        ///polarity
        ckpol: u1 = 0,
        ///I2SSTD [4:5]
        ///I2S standard selection
        i2sstd: u2 = 0,
        _unused6: u1 = 0,
        ///PCMSYNC [7:7]
        ///PCM frame synchronization
        pcmsync: u1 = 0,
        ///I2SCFG [8:9]
        ///I2S configuration mode
        i2scfg: u2 = 0,
        ///I2SE [10:10]
        ///I2S Enable
        i2se: u1 = 0,
        ///I2SMOD [11:11]
        ///I2S mode selection
        i2smod: u1 = 0,
        _unused12: u20 = 0,
    };
    ///I2S configuration register
    pub const i2scfgr = Register(i2scfgr_val).init(0x40003C00 + 0x1C);

    //////////////////////////
    ///I2SPR
    const i2spr_val = packed struct {
        ///I2SDIV [0:7]
        ///I2S Linear prescaler
        i2sdiv: u8 = 16,
        ///ODD [8:8]
        ///Odd factor for the
        ///prescaler
        odd: u1 = 0,
        ///MCKOE [9:9]
        ///Master clock output enable
        mckoe: u1 = 0,
        _unused10: u22 = 0,
    };
    ///I2S prescaler register
    pub const i2spr = Register(i2spr_val).init(0x40003C00 + 0x20);
};

///Universal synchronous asynchronous receiver
///transmitter
pub const usart1 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///PE [0:0]
        ///Parity error
        pe: u1 = 0,
        ///FE [1:1]
        ///Framing error
        fe: u1 = 0,
        ///NE [2:2]
        ///Noise error flag
        ne: u1 = 0,
        ///ORE [3:3]
        ///Overrun error
        ore: u1 = 0,
        ///IDLE [4:4]
        ///IDLE line detected
        idle: u1 = 0,
        ///RXNE [5:5]
        ///Read data register not
        ///empty
        rxne: u1 = 0,
        ///TC [6:6]
        ///Transmission complete
        tc: u1 = 1,
        ///TXE [7:7]
        ///Transmit data register
        ///empty
        txe: u1 = 1,
        ///LBD [8:8]
        ///LIN break detection flag
        lbd: u1 = 0,
        ///CTS [9:9]
        ///CTS flag
        cts: u1 = 0,
        _unused10: u22 = 0,
    };
    ///Status register
    pub const sr = Register(sr_val).init(0x40013800 + 0x0);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:8]
        ///Data value
        dr: u9 = 0,
        _unused9: u23 = 0,
    };
    ///Data register
    pub const dr = Register(dr_val).init(0x40013800 + 0x4);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///DIV_Fraction [0:3]
        ///fraction of USARTDIV
        div_fraction: u4 = 0,
        ///DIV_Mantissa [4:15]
        ///mantissa of USARTDIV
        div_mantissa: u12 = 0,
        _unused16: u16 = 0,
    };
    ///Baud rate register
    pub const brr = Register(brr_val).init(0x40013800 + 0x8);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///SBK [0:0]
        ///Send break
        sbk: u1 = 0,
        ///RWU [1:1]
        ///Receiver wakeup
        rwu: u1 = 0,
        ///RE [2:2]
        ///Receiver enable
        re: u1 = 0,
        ///TE [3:3]
        ///Transmitter enable
        te: u1 = 0,
        ///IDLEIE [4:4]
        ///IDLE interrupt enable
        idleie: u1 = 0,
        ///RXNEIE [5:5]
        ///RXNE interrupt enable
        rxneie: u1 = 0,
        ///TCIE [6:6]
        ///Transmission complete interrupt
        ///enable
        tcie: u1 = 0,
        ///TXEIE [7:7]
        ///TXE interrupt enable
        txeie: u1 = 0,
        ///PEIE [8:8]
        ///PE interrupt enable
        peie: u1 = 0,
        ///PS [9:9]
        ///Parity selection
        ps: u1 = 0,
        ///PCE [10:10]
        ///Parity control enable
        pce: u1 = 0,
        ///WAKE [11:11]
        ///Wakeup method
        wake: u1 = 0,
        ///M [12:12]
        ///Word length
        m: u1 = 0,
        ///UE [13:13]
        ///USART enable
        ue: u1 = 0,
        _unused14: u18 = 0,
    };
    ///Control register 1
    pub const cr1 = Register(cr1_val).init(0x40013800 + 0xC);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADD [0:3]
        ///Address of the USART node
        add: u4 = 0,
        _unused4: u1 = 0,
        ///LBDL [5:5]
        ///lin break detection length
        lbdl: u1 = 0,
        ///LBDIE [6:6]
        ///LIN break detection interrupt
        ///enable
        lbdie: u1 = 0,
        _unused7: u1 = 0,
        ///LBCL [8:8]
        ///Last bit clock pulse
        lbcl: u1 = 0,
        ///CPHA [9:9]
        ///Clock phase
        cpha: u1 = 0,
        ///CPOL [10:10]
        ///Clock polarity
        cpol: u1 = 0,
        ///CLKEN [11:11]
        ///Clock enable
        clken: u1 = 0,
        ///STOP [12:13]
        ///STOP bits
        stop: u2 = 0,
        ///LINEN [14:14]
        ///LIN mode enable
        linen: u1 = 0,
        _unused15: u17 = 0,
    };
    ///Control register 2
    pub const cr2 = Register(cr2_val).init(0x40013800 + 0x10);

    //////////////////////////
    ///CR3
    const cr3_val = packed struct {
        ///EIE [0:0]
        ///Error interrupt enable
        eie: u1 = 0,
        ///IREN [1:1]
        ///IrDA mode enable
        iren: u1 = 0,
        ///IRLP [2:2]
        ///IrDA low-power
        irlp: u1 = 0,
        ///HDSEL [3:3]
        ///Half-duplex selection
        hdsel: u1 = 0,
        ///NACK [4:4]
        ///Smartcard NACK enable
        nack: u1 = 0,
        ///SCEN [5:5]
        ///Smartcard mode enable
        scen: u1 = 0,
        ///DMAR [6:6]
        ///DMA enable receiver
        dmar: u1 = 0,
        ///DMAT [7:7]
        ///DMA enable transmitter
        dmat: u1 = 0,
        ///RTSE [8:8]
        ///RTS enable
        rtse: u1 = 0,
        ///CTSE [9:9]
        ///CTS enable
        ctse: u1 = 0,
        ///CTSIE [10:10]
        ///CTS interrupt enable
        ctsie: u1 = 0,
        _unused11: u21 = 0,
    };
    ///Control register 3
    pub const cr3 = Register(cr3_val).init(0x40013800 + 0x14);

    //////////////////////////
    ///GTPR
    const gtpr_val = packed struct {
        ///PSC [0:7]
        ///Prescaler value
        psc: u8 = 0,
        ///GT [8:15]
        ///Guard time value
        gt: u8 = 0,
        _unused16: u16 = 0,
    };
    ///Guard time and prescaler
    ///register
    pub const gtpr = Register(gtpr_val).init(0x40013800 + 0x18);
};

///Universal synchronous asynchronous receiver
///transmitter
pub const usart2 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///PE [0:0]
        ///Parity error
        pe: u1 = 0,
        ///FE [1:1]
        ///Framing error
        fe: u1 = 0,
        ///NE [2:2]
        ///Noise error flag
        ne: u1 = 0,
        ///ORE [3:3]
        ///Overrun error
        ore: u1 = 0,
        ///IDLE [4:4]
        ///IDLE line detected
        idle: u1 = 0,
        ///RXNE [5:5]
        ///Read data register not
        ///empty
        rxne: u1 = 0,
        ///TC [6:6]
        ///Transmission complete
        tc: u1 = 1,
        ///TXE [7:7]
        ///Transmit data register
        ///empty
        txe: u1 = 1,
        ///LBD [8:8]
        ///LIN break detection flag
        lbd: u1 = 0,
        ///CTS [9:9]
        ///CTS flag
        cts: u1 = 0,
        _unused10: u22 = 0,
    };
    ///Status register
    pub const sr = Register(sr_val).init(0x40004400 + 0x0);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:8]
        ///Data value
        dr: u9 = 0,
        _unused9: u23 = 0,
    };
    ///Data register
    pub const dr = Register(dr_val).init(0x40004400 + 0x4);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///DIV_Fraction [0:3]
        ///fraction of USARTDIV
        div_fraction: u4 = 0,
        ///DIV_Mantissa [4:15]
        ///mantissa of USARTDIV
        div_mantissa: u12 = 0,
        _unused16: u16 = 0,
    };
    ///Baud rate register
    pub const brr = Register(brr_val).init(0x40004400 + 0x8);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///SBK [0:0]
        ///Send break
        sbk: u1 = 0,
        ///RWU [1:1]
        ///Receiver wakeup
        rwu: u1 = 0,
        ///RE [2:2]
        ///Receiver enable
        re: u1 = 0,
        ///TE [3:3]
        ///Transmitter enable
        te: u1 = 0,
        ///IDLEIE [4:4]
        ///IDLE interrupt enable
        idleie: u1 = 0,
        ///RXNEIE [5:5]
        ///RXNE interrupt enable
        rxneie: u1 = 0,
        ///TCIE [6:6]
        ///Transmission complete interrupt
        ///enable
        tcie: u1 = 0,
        ///TXEIE [7:7]
        ///TXE interrupt enable
        txeie: u1 = 0,
        ///PEIE [8:8]
        ///PE interrupt enable
        peie: u1 = 0,
        ///PS [9:9]
        ///Parity selection
        ps: u1 = 0,
        ///PCE [10:10]
        ///Parity control enable
        pce: u1 = 0,
        ///WAKE [11:11]
        ///Wakeup method
        wake: u1 = 0,
        ///M [12:12]
        ///Word length
        m: u1 = 0,
        ///UE [13:13]
        ///USART enable
        ue: u1 = 0,
        _unused14: u18 = 0,
    };
    ///Control register 1
    pub const cr1 = Register(cr1_val).init(0x40004400 + 0xC);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADD [0:3]
        ///Address of the USART node
        add: u4 = 0,
        _unused4: u1 = 0,
        ///LBDL [5:5]
        ///lin break detection length
        lbdl: u1 = 0,
        ///LBDIE [6:6]
        ///LIN break detection interrupt
        ///enable
        lbdie: u1 = 0,
        _unused7: u1 = 0,
        ///LBCL [8:8]
        ///Last bit clock pulse
        lbcl: u1 = 0,
        ///CPHA [9:9]
        ///Clock phase
        cpha: u1 = 0,
        ///CPOL [10:10]
        ///Clock polarity
        cpol: u1 = 0,
        ///CLKEN [11:11]
        ///Clock enable
        clken: u1 = 0,
        ///STOP [12:13]
        ///STOP bits
        stop: u2 = 0,
        ///LINEN [14:14]
        ///LIN mode enable
        linen: u1 = 0,
        _unused15: u17 = 0,
    };
    ///Control register 2
    pub const cr2 = Register(cr2_val).init(0x40004400 + 0x10);

    //////////////////////////
    ///CR3
    const cr3_val = packed struct {
        ///EIE [0:0]
        ///Error interrupt enable
        eie: u1 = 0,
        ///IREN [1:1]
        ///IrDA mode enable
        iren: u1 = 0,
        ///IRLP [2:2]
        ///IrDA low-power
        irlp: u1 = 0,
        ///HDSEL [3:3]
        ///Half-duplex selection
        hdsel: u1 = 0,
        ///NACK [4:4]
        ///Smartcard NACK enable
        nack: u1 = 0,
        ///SCEN [5:5]
        ///Smartcard mode enable
        scen: u1 = 0,
        ///DMAR [6:6]
        ///DMA enable receiver
        dmar: u1 = 0,
        ///DMAT [7:7]
        ///DMA enable transmitter
        dmat: u1 = 0,
        ///RTSE [8:8]
        ///RTS enable
        rtse: u1 = 0,
        ///CTSE [9:9]
        ///CTS enable
        ctse: u1 = 0,
        ///CTSIE [10:10]
        ///CTS interrupt enable
        ctsie: u1 = 0,
        _unused11: u21 = 0,
    };
    ///Control register 3
    pub const cr3 = Register(cr3_val).init(0x40004400 + 0x14);

    //////////////////////////
    ///GTPR
    const gtpr_val = packed struct {
        ///PSC [0:7]
        ///Prescaler value
        psc: u8 = 0,
        ///GT [8:15]
        ///Guard time value
        gt: u8 = 0,
        _unused16: u16 = 0,
    };
    ///Guard time and prescaler
    ///register
    pub const gtpr = Register(gtpr_val).init(0x40004400 + 0x18);
};

///Universal synchronous asynchronous receiver
///transmitter
pub const usart3 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///PE [0:0]
        ///Parity error
        pe: u1 = 0,
        ///FE [1:1]
        ///Framing error
        fe: u1 = 0,
        ///NE [2:2]
        ///Noise error flag
        ne: u1 = 0,
        ///ORE [3:3]
        ///Overrun error
        ore: u1 = 0,
        ///IDLE [4:4]
        ///IDLE line detected
        idle: u1 = 0,
        ///RXNE [5:5]
        ///Read data register not
        ///empty
        rxne: u1 = 0,
        ///TC [6:6]
        ///Transmission complete
        tc: u1 = 1,
        ///TXE [7:7]
        ///Transmit data register
        ///empty
        txe: u1 = 1,
        ///LBD [8:8]
        ///LIN break detection flag
        lbd: u1 = 0,
        ///CTS [9:9]
        ///CTS flag
        cts: u1 = 0,
        _unused10: u22 = 0,
    };
    ///Status register
    pub const sr = Register(sr_val).init(0x40004800 + 0x0);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:8]
        ///Data value
        dr: u9 = 0,
        _unused9: u23 = 0,
    };
    ///Data register
    pub const dr = Register(dr_val).init(0x40004800 + 0x4);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///DIV_Fraction [0:3]
        ///fraction of USARTDIV
        div_fraction: u4 = 0,
        ///DIV_Mantissa [4:15]
        ///mantissa of USARTDIV
        div_mantissa: u12 = 0,
        _unused16: u16 = 0,
    };
    ///Baud rate register
    pub const brr = Register(brr_val).init(0x40004800 + 0x8);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///SBK [0:0]
        ///Send break
        sbk: u1 = 0,
        ///RWU [1:1]
        ///Receiver wakeup
        rwu: u1 = 0,
        ///RE [2:2]
        ///Receiver enable
        re: u1 = 0,
        ///TE [3:3]
        ///Transmitter enable
        te: u1 = 0,
        ///IDLEIE [4:4]
        ///IDLE interrupt enable
        idleie: u1 = 0,
        ///RXNEIE [5:5]
        ///RXNE interrupt enable
        rxneie: u1 = 0,
        ///TCIE [6:6]
        ///Transmission complete interrupt
        ///enable
        tcie: u1 = 0,
        ///TXEIE [7:7]
        ///TXE interrupt enable
        txeie: u1 = 0,
        ///PEIE [8:8]
        ///PE interrupt enable
        peie: u1 = 0,
        ///PS [9:9]
        ///Parity selection
        ps: u1 = 0,
        ///PCE [10:10]
        ///Parity control enable
        pce: u1 = 0,
        ///WAKE [11:11]
        ///Wakeup method
        wake: u1 = 0,
        ///M [12:12]
        ///Word length
        m: u1 = 0,
        ///UE [13:13]
        ///USART enable
        ue: u1 = 0,
        _unused14: u18 = 0,
    };
    ///Control register 1
    pub const cr1 = Register(cr1_val).init(0x40004800 + 0xC);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADD [0:3]
        ///Address of the USART node
        add: u4 = 0,
        _unused4: u1 = 0,
        ///LBDL [5:5]
        ///lin break detection length
        lbdl: u1 = 0,
        ///LBDIE [6:6]
        ///LIN break detection interrupt
        ///enable
        lbdie: u1 = 0,
        _unused7: u1 = 0,
        ///LBCL [8:8]
        ///Last bit clock pulse
        lbcl: u1 = 0,
        ///CPHA [9:9]
        ///Clock phase
        cpha: u1 = 0,
        ///CPOL [10:10]
        ///Clock polarity
        cpol: u1 = 0,
        ///CLKEN [11:11]
        ///Clock enable
        clken: u1 = 0,
        ///STOP [12:13]
        ///STOP bits
        stop: u2 = 0,
        ///LINEN [14:14]
        ///LIN mode enable
        linen: u1 = 0,
        _unused15: u17 = 0,
    };
    ///Control register 2
    pub const cr2 = Register(cr2_val).init(0x40004800 + 0x10);

    //////////////////////////
    ///CR3
    const cr3_val = packed struct {
        ///EIE [0:0]
        ///Error interrupt enable
        eie: u1 = 0,
        ///IREN [1:1]
        ///IrDA mode enable
        iren: u1 = 0,
        ///IRLP [2:2]
        ///IrDA low-power
        irlp: u1 = 0,
        ///HDSEL [3:3]
        ///Half-duplex selection
        hdsel: u1 = 0,
        ///NACK [4:4]
        ///Smartcard NACK enable
        nack: u1 = 0,
        ///SCEN [5:5]
        ///Smartcard mode enable
        scen: u1 = 0,
        ///DMAR [6:6]
        ///DMA enable receiver
        dmar: u1 = 0,
        ///DMAT [7:7]
        ///DMA enable transmitter
        dmat: u1 = 0,
        ///RTSE [8:8]
        ///RTS enable
        rtse: u1 = 0,
        ///CTSE [9:9]
        ///CTS enable
        ctse: u1 = 0,
        ///CTSIE [10:10]
        ///CTS interrupt enable
        ctsie: u1 = 0,
        _unused11: u21 = 0,
    };
    ///Control register 3
    pub const cr3 = Register(cr3_val).init(0x40004800 + 0x14);

    //////////////////////////
    ///GTPR
    const gtpr_val = packed struct {
        ///PSC [0:7]
        ///Prescaler value
        psc: u8 = 0,
        ///GT [8:15]
        ///Guard time value
        gt: u8 = 0,
        _unused16: u16 = 0,
    };
    ///Guard time and prescaler
    ///register
    pub const gtpr = Register(gtpr_val).init(0x40004800 + 0x18);
};

///Analog to digital converter
pub const adc1 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///AWD [0:0]
        ///Analog watchdog flag
        awd: u1 = 0,
        ///EOC [1:1]
        ///Regular channel end of
        ///conversion
        eoc: u1 = 0,
        ///JEOC [2:2]
        ///Injected channel end of
        ///conversion
        jeoc: u1 = 0,
        ///JSTRT [3:3]
        ///Injected channel start
        ///flag
        jstrt: u1 = 0,
        ///STRT [4:4]
        ///Regular channel start flag
        strt: u1 = 0,
        _unused5: u27 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40012400 + 0x0);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///AWDCH [0:4]
        ///Analog watchdog channel select
        ///bits
        awdch: u5 = 0,
        ///EOCIE [5:5]
        ///Interrupt enable for EOC
        eocie: u1 = 0,
        ///AWDIE [6:6]
        ///Analog watchdog interrupt
        ///enable
        awdie: u1 = 0,
        ///JEOCIE [7:7]
        ///Interrupt enable for injected
        ///channels
        jeocie: u1 = 0,
        ///SCAN [8:8]
        ///Scan mode
        scan: u1 = 0,
        ///AWDSGL [9:9]
        ///Enable the watchdog on a single channel
        ///in scan mode
        awdsgl: u1 = 0,
        ///JAUTO [10:10]
        ///Automatic injected group
        ///conversion
        jauto: u1 = 0,
        ///DISCEN [11:11]
        ///Discontinuous mode on regular
        ///channels
        discen: u1 = 0,
        ///JDISCEN [12:12]
        ///Discontinuous mode on injected
        ///channels
        jdiscen: u1 = 0,
        ///DISCNUM [13:15]
        ///Discontinuous mode channel
        ///count
        discnum: u3 = 0,
        ///DUALMOD [16:19]
        ///Dual mode selection
        dualmod: u4 = 0,
        _unused20: u2 = 0,
        ///JAWDEN [22:22]
        ///Analog watchdog enable on injected
        ///channels
        jawden: u1 = 0,
        ///AWDEN [23:23]
        ///Analog watchdog enable on regular
        ///channels
        awden: u1 = 0,
        _unused24: u8 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40012400 + 0x4);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADON [0:0]
        ///A/D converter ON / OFF
        adon: u1 = 0,
        ///CONT [1:1]
        ///Continuous conversion
        cont: u1 = 0,
        ///CAL [2:2]
        ///A/D calibration
        cal: u1 = 0,
        ///RSTCAL [3:3]
        ///Reset calibration
        rstcal: u1 = 0,
        _unused4: u4 = 0,
        ///DMA [8:8]
        ///Direct memory access mode
        dma: u1 = 0,
        _unused9: u2 = 0,
        ///ALIGN [11:11]
        ///Data alignment
        _align: u1 = 0,
        ///JEXTSEL [12:14]
        ///External event select for injected
        ///group
        jextsel: u3 = 0,
        ///JEXTTRIG [15:15]
        ///External trigger conversion mode for
        ///injected channels
        jexttrig: u1 = 0,
        _unused16: u1 = 0,
        ///EXTSEL [17:19]
        ///External event select for regular
        ///group
        extsel: u3 = 0,
        ///EXTTRIG [20:20]
        ///External trigger conversion mode for
        ///regular channels
        exttrig: u1 = 0,
        ///JSWSTART [21:21]
        ///Start conversion of injected
        ///channels
        jswstart: u1 = 0,
        ///SWSTART [22:22]
        ///Start conversion of regular
        ///channels
        swstart: u1 = 0,
        ///TSVREFE [23:23]
        ///Temperature sensor and VREFINT
        ///enable
        tsvrefe: u1 = 0,
        _unused24: u8 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40012400 + 0x8);

    //////////////////////////
    ///SMPR1
    const smpr1_val = packed struct {
        ///SMP10 [0:2]
        ///Channel 10 sample time
        ///selection
        smp10: u3 = 0,
        ///SMP11 [3:5]
        ///Channel 11 sample time
        ///selection
        smp11: u3 = 0,
        ///SMP12 [6:8]
        ///Channel 12 sample time
        ///selection
        smp12: u3 = 0,
        ///SMP13 [9:11]
        ///Channel 13 sample time
        ///selection
        smp13: u3 = 0,
        ///SMP14 [12:14]
        ///Channel 14 sample time
        ///selection
        smp14: u3 = 0,
        ///SMP15 [15:17]
        ///Channel 15 sample time
        ///selection
        smp15: u3 = 0,
        ///SMP16 [18:20]
        ///Channel 16 sample time
        ///selection
        smp16: u3 = 0,
        ///SMP17 [21:23]
        ///Channel 17 sample time
        ///selection
        smp17: u3 = 0,
        _unused24: u8 = 0,
    };
    ///sample time register 1
    pub const smpr1 = Register(smpr1_val).init(0x40012400 + 0xC);

    //////////////////////////
    ///SMPR2
    const smpr2_val = packed struct {
        ///SMP0 [0:2]
        ///Channel 0 sample time
        ///selection
        smp0: u3 = 0,
        ///SMP1 [3:5]
        ///Channel 1 sample time
        ///selection
        smp1: u3 = 0,
        ///SMP2 [6:8]
        ///Channel 2 sample time
        ///selection
        smp2: u3 = 0,
        ///SMP3 [9:11]
        ///Channel 3 sample time
        ///selection
        smp3: u3 = 0,
        ///SMP4 [12:14]
        ///Channel 4 sample time
        ///selection
        smp4: u3 = 0,
        ///SMP5 [15:17]
        ///Channel 5 sample time
        ///selection
        smp5: u3 = 0,
        ///SMP6 [18:20]
        ///Channel 6 sample time
        ///selection
        smp6: u3 = 0,
        ///SMP7 [21:23]
        ///Channel 7 sample time
        ///selection
        smp7: u3 = 0,
        ///SMP8 [24:26]
        ///Channel 8 sample time
        ///selection
        smp8: u3 = 0,
        ///SMP9 [27:29]
        ///Channel 9 sample time
        ///selection
        smp9: u3 = 0,
        _unused30: u2 = 0,
    };
    ///sample time register 2
    pub const smpr2 = Register(smpr2_val).init(0x40012400 + 0x10);

    //////////////////////////
    ///JOFR1
    const jofr1_val = packed struct {
        ///JOFFSET1 [0:11]
        ///Data offset for injected channel
        ///x
        joffset1: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr1 = Register(jofr1_val).init(0x40012400 + 0x14);

    //////////////////////////
    ///JOFR2
    const jofr2_val = packed struct {
        ///JOFFSET2 [0:11]
        ///Data offset for injected channel
        ///x
        joffset2: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr2 = Register(jofr2_val).init(0x40012400 + 0x18);

    //////////////////////////
    ///JOFR3
    const jofr3_val = packed struct {
        ///JOFFSET3 [0:11]
        ///Data offset for injected channel
        ///x
        joffset3: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr3 = Register(jofr3_val).init(0x40012400 + 0x1C);

    //////////////////////////
    ///JOFR4
    const jofr4_val = packed struct {
        ///JOFFSET4 [0:11]
        ///Data offset for injected channel
        ///x
        joffset4: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr4 = Register(jofr4_val).init(0x40012400 + 0x20);

    //////////////////////////
    ///HTR
    const htr_val = packed struct {
        ///HT [0:11]
        ///Analog watchdog higher
        ///threshold
        ht: u12 = 4095,
        _unused12: u20 = 0,
    };
    ///watchdog higher threshold
    ///register
    pub const htr = Register(htr_val).init(0x40012400 + 0x24);

    //////////////////////////
    ///LTR
    const ltr_val = packed struct {
        ///LT [0:11]
        ///Analog watchdog lower
        ///threshold
        lt: u12 = 0,
        _unused12: u20 = 0,
    };
    ///watchdog lower threshold
    ///register
    pub const ltr = Register(ltr_val).init(0x40012400 + 0x28);

    //////////////////////////
    ///SQR1
    const sqr1_val = packed struct {
        ///SQ13 [0:4]
        ///13th conversion in regular
        ///sequence
        sq13: u5 = 0,
        ///SQ14 [5:9]
        ///14th conversion in regular
        ///sequence
        sq14: u5 = 0,
        ///SQ15 [10:14]
        ///15th conversion in regular
        ///sequence
        sq15: u5 = 0,
        ///SQ16 [15:19]
        ///16th conversion in regular
        ///sequence
        sq16: u5 = 0,
        ///L [20:23]
        ///Regular channel sequence
        ///length
        l: u4 = 0,
        _unused24: u8 = 0,
    };
    ///regular sequence register 1
    pub const sqr1 = Register(sqr1_val).init(0x40012400 + 0x2C);

    //////////////////////////
    ///SQR2
    const sqr2_val = packed struct {
        ///SQ7 [0:4]
        ///7th conversion in regular
        ///sequence
        sq7: u5 = 0,
        ///SQ8 [5:9]
        ///8th conversion in regular
        ///sequence
        sq8: u5 = 0,
        ///SQ9 [10:14]
        ///9th conversion in regular
        ///sequence
        sq9: u5 = 0,
        ///SQ10 [15:19]
        ///10th conversion in regular
        ///sequence
        sq10: u5 = 0,
        ///SQ11 [20:24]
        ///11th conversion in regular
        ///sequence
        sq11: u5 = 0,
        ///SQ12 [25:29]
        ///12th conversion in regular
        ///sequence
        sq12: u5 = 0,
        _unused30: u2 = 0,
    };
    ///regular sequence register 2
    pub const sqr2 = Register(sqr2_val).init(0x40012400 + 0x30);

    //////////////////////////
    ///SQR3
    const sqr3_val = packed struct {
        ///SQ1 [0:4]
        ///1st conversion in regular
        ///sequence
        sq1: u5 = 0,
        ///SQ2 [5:9]
        ///2nd conversion in regular
        ///sequence
        sq2: u5 = 0,
        ///SQ3 [10:14]
        ///3rd conversion in regular
        ///sequence
        sq3: u5 = 0,
        ///SQ4 [15:19]
        ///4th conversion in regular
        ///sequence
        sq4: u5 = 0,
        ///SQ5 [20:24]
        ///5th conversion in regular
        ///sequence
        sq5: u5 = 0,
        ///SQ6 [25:29]
        ///6th conversion in regular
        ///sequence
        sq6: u5 = 0,
        _unused30: u2 = 0,
    };
    ///regular sequence register 3
    pub const sqr3 = Register(sqr3_val).init(0x40012400 + 0x34);

    //////////////////////////
    ///JSQR
    const jsqr_val = packed struct {
        ///JSQ1 [0:4]
        ///1st conversion in injected
        ///sequence
        jsq1: u5 = 0,
        ///JSQ2 [5:9]
        ///2nd conversion in injected
        ///sequence
        jsq2: u5 = 0,
        ///JSQ3 [10:14]
        ///3rd conversion in injected
        ///sequence
        jsq3: u5 = 0,
        ///JSQ4 [15:19]
        ///4th conversion in injected
        ///sequence
        jsq4: u5 = 0,
        ///JL [20:21]
        ///Injected sequence length
        jl: u2 = 0,
        _unused22: u10 = 0,
    };
    ///injected sequence register
    pub const jsqr = Register(jsqr_val).init(0x40012400 + 0x38);

    //////////////////////////
    ///JDR1
    const jdr1_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr1 = RegisterRW(jdr1_val, void).init(0x40012400 + 0x3C);

    //////////////////////////
    ///JDR2
    const jdr2_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr2 = RegisterRW(jdr2_val, void).init(0x40012400 + 0x40);

    //////////////////////////
    ///JDR3
    const jdr3_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr3 = RegisterRW(jdr3_val, void).init(0x40012400 + 0x44);

    //////////////////////////
    ///JDR4
    const jdr4_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr4 = RegisterRW(jdr4_val, void).init(0x40012400 + 0x48);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DATA [0:15]
        ///Regular data
        data: u16 = 0,
        ///ADC2DATA [16:31]
        ///ADC2 data
        adc2data: u16 = 0,
    };
    ///regular data register
    pub const dr = RegisterRW(dr_val, void).init(0x40012400 + 0x4C);
};

///Analog to digital converter
pub const adc2 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///AWD [0:0]
        ///Analog watchdog flag
        awd: u1 = 0,
        ///EOC [1:1]
        ///Regular channel end of
        ///conversion
        eoc: u1 = 0,
        ///JEOC [2:2]
        ///Injected channel end of
        ///conversion
        jeoc: u1 = 0,
        ///JSTRT [3:3]
        ///Injected channel start
        ///flag
        jstrt: u1 = 0,
        ///STRT [4:4]
        ///Regular channel start flag
        strt: u1 = 0,
        _unused5: u27 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40012800 + 0x0);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///AWDCH [0:4]
        ///Analog watchdog channel select
        ///bits
        awdch: u5 = 0,
        ///EOCIE [5:5]
        ///Interrupt enable for EOC
        eocie: u1 = 0,
        ///AWDIE [6:6]
        ///Analog watchdog interrupt
        ///enable
        awdie: u1 = 0,
        ///JEOCIE [7:7]
        ///Interrupt enable for injected
        ///channels
        jeocie: u1 = 0,
        ///SCAN [8:8]
        ///Scan mode
        scan: u1 = 0,
        ///AWDSGL [9:9]
        ///Enable the watchdog on a single channel
        ///in scan mode
        awdsgl: u1 = 0,
        ///JAUTO [10:10]
        ///Automatic injected group
        ///conversion
        jauto: u1 = 0,
        ///DISCEN [11:11]
        ///Discontinuous mode on regular
        ///channels
        discen: u1 = 0,
        ///JDISCEN [12:12]
        ///Discontinuous mode on injected
        ///channels
        jdiscen: u1 = 0,
        ///DISCNUM [13:15]
        ///Discontinuous mode channel
        ///count
        discnum: u3 = 0,
        _unused16: u6 = 0,
        ///JAWDEN [22:22]
        ///Analog watchdog enable on injected
        ///channels
        jawden: u1 = 0,
        ///AWDEN [23:23]
        ///Analog watchdog enable on regular
        ///channels
        awden: u1 = 0,
        _unused24: u8 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40012800 + 0x4);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADON [0:0]
        ///A/D converter ON / OFF
        adon: u1 = 0,
        ///CONT [1:1]
        ///Continuous conversion
        cont: u1 = 0,
        ///CAL [2:2]
        ///A/D calibration
        cal: u1 = 0,
        ///RSTCAL [3:3]
        ///Reset calibration
        rstcal: u1 = 0,
        _unused4: u4 = 0,
        ///DMA [8:8]
        ///Direct memory access mode
        dma: u1 = 0,
        _unused9: u2 = 0,
        ///ALIGN [11:11]
        ///Data alignment
        _align: u1 = 0,
        ///JEXTSEL [12:14]
        ///External event select for injected
        ///group
        jextsel: u3 = 0,
        ///JEXTTRIG [15:15]
        ///External trigger conversion mode for
        ///injected channels
        jexttrig: u1 = 0,
        _unused16: u1 = 0,
        ///EXTSEL [17:19]
        ///External event select for regular
        ///group
        extsel: u3 = 0,
        ///EXTTRIG [20:20]
        ///External trigger conversion mode for
        ///regular channels
        exttrig: u1 = 0,
        ///JSWSTART [21:21]
        ///Start conversion of injected
        ///channels
        jswstart: u1 = 0,
        ///SWSTART [22:22]
        ///Start conversion of regular
        ///channels
        swstart: u1 = 0,
        ///TSVREFE [23:23]
        ///Temperature sensor and VREFINT
        ///enable
        tsvrefe: u1 = 0,
        _unused24: u8 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40012800 + 0x8);

    //////////////////////////
    ///SMPR1
    const smpr1_val = packed struct {
        ///SMP10 [0:2]
        ///Channel 10 sample time
        ///selection
        smp10: u3 = 0,
        ///SMP11 [3:5]
        ///Channel 11 sample time
        ///selection
        smp11: u3 = 0,
        ///SMP12 [6:8]
        ///Channel 12 sample time
        ///selection
        smp12: u3 = 0,
        ///SMP13 [9:11]
        ///Channel 13 sample time
        ///selection
        smp13: u3 = 0,
        ///SMP14 [12:14]
        ///Channel 14 sample time
        ///selection
        smp14: u3 = 0,
        ///SMP15 [15:17]
        ///Channel 15 sample time
        ///selection
        smp15: u3 = 0,
        ///SMP16 [18:20]
        ///Channel 16 sample time
        ///selection
        smp16: u3 = 0,
        ///SMP17 [21:23]
        ///Channel 17 sample time
        ///selection
        smp17: u3 = 0,
        _unused24: u8 = 0,
    };
    ///sample time register 1
    pub const smpr1 = Register(smpr1_val).init(0x40012800 + 0xC);

    //////////////////////////
    ///SMPR2
    const smpr2_val = packed struct {
        ///SMP0 [0:2]
        ///Channel 0 sample time
        ///selection
        smp0: u3 = 0,
        ///SMP1 [3:5]
        ///Channel 1 sample time
        ///selection
        smp1: u3 = 0,
        ///SMP2 [6:8]
        ///Channel 2 sample time
        ///selection
        smp2: u3 = 0,
        ///SMP3 [9:11]
        ///Channel 3 sample time
        ///selection
        smp3: u3 = 0,
        ///SMP4 [12:14]
        ///Channel 4 sample time
        ///selection
        smp4: u3 = 0,
        ///SMP5 [15:17]
        ///Channel 5 sample time
        ///selection
        smp5: u3 = 0,
        ///SMP6 [18:20]
        ///Channel 6 sample time
        ///selection
        smp6: u3 = 0,
        ///SMP7 [21:23]
        ///Channel 7 sample time
        ///selection
        smp7: u3 = 0,
        ///SMP8 [24:26]
        ///Channel 8 sample time
        ///selection
        smp8: u3 = 0,
        ///SMP9 [27:29]
        ///Channel 9 sample time
        ///selection
        smp9: u3 = 0,
        _unused30: u2 = 0,
    };
    ///sample time register 2
    pub const smpr2 = Register(smpr2_val).init(0x40012800 + 0x10);

    //////////////////////////
    ///JOFR1
    const jofr1_val = packed struct {
        ///JOFFSET1 [0:11]
        ///Data offset for injected channel
        ///x
        joffset1: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr1 = Register(jofr1_val).init(0x40012800 + 0x14);

    //////////////////////////
    ///JOFR2
    const jofr2_val = packed struct {
        ///JOFFSET2 [0:11]
        ///Data offset for injected channel
        ///x
        joffset2: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr2 = Register(jofr2_val).init(0x40012800 + 0x18);

    //////////////////////////
    ///JOFR3
    const jofr3_val = packed struct {
        ///JOFFSET3 [0:11]
        ///Data offset for injected channel
        ///x
        joffset3: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr3 = Register(jofr3_val).init(0x40012800 + 0x1C);

    //////////////////////////
    ///JOFR4
    const jofr4_val = packed struct {
        ///JOFFSET4 [0:11]
        ///Data offset for injected channel
        ///x
        joffset4: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr4 = Register(jofr4_val).init(0x40012800 + 0x20);

    //////////////////////////
    ///HTR
    const htr_val = packed struct {
        ///HT [0:11]
        ///Analog watchdog higher
        ///threshold
        ht: u12 = 4095,
        _unused12: u20 = 0,
    };
    ///watchdog higher threshold
    ///register
    pub const htr = Register(htr_val).init(0x40012800 + 0x24);

    //////////////////////////
    ///LTR
    const ltr_val = packed struct {
        ///LT [0:11]
        ///Analog watchdog lower
        ///threshold
        lt: u12 = 0,
        _unused12: u20 = 0,
    };
    ///watchdog lower threshold
    ///register
    pub const ltr = Register(ltr_val).init(0x40012800 + 0x28);

    //////////////////////////
    ///SQR1
    const sqr1_val = packed struct {
        ///SQ13 [0:4]
        ///13th conversion in regular
        ///sequence
        sq13: u5 = 0,
        ///SQ14 [5:9]
        ///14th conversion in regular
        ///sequence
        sq14: u5 = 0,
        ///SQ15 [10:14]
        ///15th conversion in regular
        ///sequence
        sq15: u5 = 0,
        ///SQ16 [15:19]
        ///16th conversion in regular
        ///sequence
        sq16: u5 = 0,
        ///L [20:23]
        ///Regular channel sequence
        ///length
        l: u4 = 0,
        _unused24: u8 = 0,
    };
    ///regular sequence register 1
    pub const sqr1 = Register(sqr1_val).init(0x40012800 + 0x2C);

    //////////////////////////
    ///SQR2
    const sqr2_val = packed struct {
        ///SQ7 [0:4]
        ///7th conversion in regular
        ///sequence
        sq7: u5 = 0,
        ///SQ8 [5:9]
        ///8th conversion in regular
        ///sequence
        sq8: u5 = 0,
        ///SQ9 [10:14]
        ///9th conversion in regular
        ///sequence
        sq9: u5 = 0,
        ///SQ10 [15:19]
        ///10th conversion in regular
        ///sequence
        sq10: u5 = 0,
        ///SQ11 [20:24]
        ///11th conversion in regular
        ///sequence
        sq11: u5 = 0,
        ///SQ12 [25:29]
        ///12th conversion in regular
        ///sequence
        sq12: u5 = 0,
        _unused30: u2 = 0,
    };
    ///regular sequence register 2
    pub const sqr2 = Register(sqr2_val).init(0x40012800 + 0x30);

    //////////////////////////
    ///SQR3
    const sqr3_val = packed struct {
        ///SQ1 [0:4]
        ///1st conversion in regular
        ///sequence
        sq1: u5 = 0,
        ///SQ2 [5:9]
        ///2nd conversion in regular
        ///sequence
        sq2: u5 = 0,
        ///SQ3 [10:14]
        ///3rd conversion in regular
        ///sequence
        sq3: u5 = 0,
        ///SQ4 [15:19]
        ///4th conversion in regular
        ///sequence
        sq4: u5 = 0,
        ///SQ5 [20:24]
        ///5th conversion in regular
        ///sequence
        sq5: u5 = 0,
        ///SQ6 [25:29]
        ///6th conversion in regular
        ///sequence
        sq6: u5 = 0,
        _unused30: u2 = 0,
    };
    ///regular sequence register 3
    pub const sqr3 = Register(sqr3_val).init(0x40012800 + 0x34);

    //////////////////////////
    ///JSQR
    const jsqr_val = packed struct {
        ///JSQ1 [0:4]
        ///1st conversion in injected
        ///sequence
        jsq1: u5 = 0,
        ///JSQ2 [5:9]
        ///2nd conversion in injected
        ///sequence
        jsq2: u5 = 0,
        ///JSQ3 [10:14]
        ///3rd conversion in injected
        ///sequence
        jsq3: u5 = 0,
        ///JSQ4 [15:19]
        ///4th conversion in injected
        ///sequence
        jsq4: u5 = 0,
        ///JL [20:21]
        ///Injected sequence length
        jl: u2 = 0,
        _unused22: u10 = 0,
    };
    ///injected sequence register
    pub const jsqr = Register(jsqr_val).init(0x40012800 + 0x38);

    //////////////////////////
    ///JDR1
    const jdr1_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr1 = RegisterRW(jdr1_val, void).init(0x40012800 + 0x3C);

    //////////////////////////
    ///JDR2
    const jdr2_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr2 = RegisterRW(jdr2_val, void).init(0x40012800 + 0x40);

    //////////////////////////
    ///JDR3
    const jdr3_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr3 = RegisterRW(jdr3_val, void).init(0x40012800 + 0x44);

    //////////////////////////
    ///JDR4
    const jdr4_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr4 = RegisterRW(jdr4_val, void).init(0x40012800 + 0x48);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DATA [0:15]
        ///Regular data
        data: u16 = 0,
        _unused16: u16 = 0,
    };
    ///regular data register
    pub const dr = RegisterRW(dr_val, void).init(0x40012800 + 0x4C);
};

///Analog to digital converter
pub const adc3 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///AWD [0:0]
        ///Analog watchdog flag
        awd: u1 = 0,
        ///EOC [1:1]
        ///Regular channel end of
        ///conversion
        eoc: u1 = 0,
        ///JEOC [2:2]
        ///Injected channel end of
        ///conversion
        jeoc: u1 = 0,
        ///JSTRT [3:3]
        ///Injected channel start
        ///flag
        jstrt: u1 = 0,
        ///STRT [4:4]
        ///Regular channel start flag
        strt: u1 = 0,
        _unused5: u27 = 0,
    };
    ///status register
    pub const sr = Register(sr_val).init(0x40013C00 + 0x0);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///AWDCH [0:4]
        ///Analog watchdog channel select
        ///bits
        awdch: u5 = 0,
        ///EOCIE [5:5]
        ///Interrupt enable for EOC
        eocie: u1 = 0,
        ///AWDIE [6:6]
        ///Analog watchdog interrupt
        ///enable
        awdie: u1 = 0,
        ///JEOCIE [7:7]
        ///Interrupt enable for injected
        ///channels
        jeocie: u1 = 0,
        ///SCAN [8:8]
        ///Scan mode
        scan: u1 = 0,
        ///AWDSGL [9:9]
        ///Enable the watchdog on a single channel
        ///in scan mode
        awdsgl: u1 = 0,
        ///JAUTO [10:10]
        ///Automatic injected group
        ///conversion
        jauto: u1 = 0,
        ///DISCEN [11:11]
        ///Discontinuous mode on regular
        ///channels
        discen: u1 = 0,
        ///JDISCEN [12:12]
        ///Discontinuous mode on injected
        ///channels
        jdiscen: u1 = 0,
        ///DISCNUM [13:15]
        ///Discontinuous mode channel
        ///count
        discnum: u3 = 0,
        _unused16: u6 = 0,
        ///JAWDEN [22:22]
        ///Analog watchdog enable on injected
        ///channels
        jawden: u1 = 0,
        ///AWDEN [23:23]
        ///Analog watchdog enable on regular
        ///channels
        awden: u1 = 0,
        _unused24: u8 = 0,
    };
    ///control register 1
    pub const cr1 = Register(cr1_val).init(0x40013C00 + 0x4);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADON [0:0]
        ///A/D converter ON / OFF
        adon: u1 = 0,
        ///CONT [1:1]
        ///Continuous conversion
        cont: u1 = 0,
        ///CAL [2:2]
        ///A/D calibration
        cal: u1 = 0,
        ///RSTCAL [3:3]
        ///Reset calibration
        rstcal: u1 = 0,
        _unused4: u4 = 0,
        ///DMA [8:8]
        ///Direct memory access mode
        dma: u1 = 0,
        _unused9: u2 = 0,
        ///ALIGN [11:11]
        ///Data alignment
        _align: u1 = 0,
        ///JEXTSEL [12:14]
        ///External event select for injected
        ///group
        jextsel: u3 = 0,
        ///JEXTTRIG [15:15]
        ///External trigger conversion mode for
        ///injected channels
        jexttrig: u1 = 0,
        _unused16: u1 = 0,
        ///EXTSEL [17:19]
        ///External event select for regular
        ///group
        extsel: u3 = 0,
        ///EXTTRIG [20:20]
        ///External trigger conversion mode for
        ///regular channels
        exttrig: u1 = 0,
        ///JSWSTART [21:21]
        ///Start conversion of injected
        ///channels
        jswstart: u1 = 0,
        ///SWSTART [22:22]
        ///Start conversion of regular
        ///channels
        swstart: u1 = 0,
        ///TSVREFE [23:23]
        ///Temperature sensor and VREFINT
        ///enable
        tsvrefe: u1 = 0,
        _unused24: u8 = 0,
    };
    ///control register 2
    pub const cr2 = Register(cr2_val).init(0x40013C00 + 0x8);

    //////////////////////////
    ///SMPR1
    const smpr1_val = packed struct {
        ///SMP10 [0:2]
        ///Channel 10 sample time
        ///selection
        smp10: u3 = 0,
        ///SMP11 [3:5]
        ///Channel 11 sample time
        ///selection
        smp11: u3 = 0,
        ///SMP12 [6:8]
        ///Channel 12 sample time
        ///selection
        smp12: u3 = 0,
        ///SMP13 [9:11]
        ///Channel 13 sample time
        ///selection
        smp13: u3 = 0,
        ///SMP14 [12:14]
        ///Channel 14 sample time
        ///selection
        smp14: u3 = 0,
        ///SMP15 [15:17]
        ///Channel 15 sample time
        ///selection
        smp15: u3 = 0,
        ///SMP16 [18:20]
        ///Channel 16 sample time
        ///selection
        smp16: u3 = 0,
        ///SMP17 [21:23]
        ///Channel 17 sample time
        ///selection
        smp17: u3 = 0,
        _unused24: u8 = 0,
    };
    ///sample time register 1
    pub const smpr1 = Register(smpr1_val).init(0x40013C00 + 0xC);

    //////////////////////////
    ///SMPR2
    const smpr2_val = packed struct {
        ///SMP0 [0:2]
        ///Channel 0 sample time
        ///selection
        smp0: u3 = 0,
        ///SMP1 [3:5]
        ///Channel 1 sample time
        ///selection
        smp1: u3 = 0,
        ///SMP2 [6:8]
        ///Channel 2 sample time
        ///selection
        smp2: u3 = 0,
        ///SMP3 [9:11]
        ///Channel 3 sample time
        ///selection
        smp3: u3 = 0,
        ///SMP4 [12:14]
        ///Channel 4 sample time
        ///selection
        smp4: u3 = 0,
        ///SMP5 [15:17]
        ///Channel 5 sample time
        ///selection
        smp5: u3 = 0,
        ///SMP6 [18:20]
        ///Channel 6 sample time
        ///selection
        smp6: u3 = 0,
        ///SMP7 [21:23]
        ///Channel 7 sample time
        ///selection
        smp7: u3 = 0,
        ///SMP8 [24:26]
        ///Channel 8 sample time
        ///selection
        smp8: u3 = 0,
        ///SMP9 [27:29]
        ///Channel 9 sample time
        ///selection
        smp9: u3 = 0,
        _unused30: u2 = 0,
    };
    ///sample time register 2
    pub const smpr2 = Register(smpr2_val).init(0x40013C00 + 0x10);

    //////////////////////////
    ///JOFR1
    const jofr1_val = packed struct {
        ///JOFFSET1 [0:11]
        ///Data offset for injected channel
        ///x
        joffset1: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr1 = Register(jofr1_val).init(0x40013C00 + 0x14);

    //////////////////////////
    ///JOFR2
    const jofr2_val = packed struct {
        ///JOFFSET2 [0:11]
        ///Data offset for injected channel
        ///x
        joffset2: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr2 = Register(jofr2_val).init(0x40013C00 + 0x18);

    //////////////////////////
    ///JOFR3
    const jofr3_val = packed struct {
        ///JOFFSET3 [0:11]
        ///Data offset for injected channel
        ///x
        joffset3: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr3 = Register(jofr3_val).init(0x40013C00 + 0x1C);

    //////////////////////////
    ///JOFR4
    const jofr4_val = packed struct {
        ///JOFFSET4 [0:11]
        ///Data offset for injected channel
        ///x
        joffset4: u12 = 0,
        _unused12: u20 = 0,
    };
    ///injected channel data offset register
    ///x
    pub const jofr4 = Register(jofr4_val).init(0x40013C00 + 0x20);

    //////////////////////////
    ///HTR
    const htr_val = packed struct {
        ///HT [0:11]
        ///Analog watchdog higher
        ///threshold
        ht: u12 = 4095,
        _unused12: u20 = 0,
    };
    ///watchdog higher threshold
    ///register
    pub const htr = Register(htr_val).init(0x40013C00 + 0x24);

    //////////////////////////
    ///LTR
    const ltr_val = packed struct {
        ///LT [0:11]
        ///Analog watchdog lower
        ///threshold
        lt: u12 = 0,
        _unused12: u20 = 0,
    };
    ///watchdog lower threshold
    ///register
    pub const ltr = Register(ltr_val).init(0x40013C00 + 0x28);

    //////////////////////////
    ///SQR1
    const sqr1_val = packed struct {
        ///SQ13 [0:4]
        ///13th conversion in regular
        ///sequence
        sq13: u5 = 0,
        ///SQ14 [5:9]
        ///14th conversion in regular
        ///sequence
        sq14: u5 = 0,
        ///SQ15 [10:14]
        ///15th conversion in regular
        ///sequence
        sq15: u5 = 0,
        ///SQ16 [15:19]
        ///16th conversion in regular
        ///sequence
        sq16: u5 = 0,
        ///L [20:23]
        ///Regular channel sequence
        ///length
        l: u4 = 0,
        _unused24: u8 = 0,
    };
    ///regular sequence register 1
    pub const sqr1 = Register(sqr1_val).init(0x40013C00 + 0x2C);

    //////////////////////////
    ///SQR2
    const sqr2_val = packed struct {
        ///SQ7 [0:4]
        ///7th conversion in regular
        ///sequence
        sq7: u5 = 0,
        ///SQ8 [5:9]
        ///8th conversion in regular
        ///sequence
        sq8: u5 = 0,
        ///SQ9 [10:14]
        ///9th conversion in regular
        ///sequence
        sq9: u5 = 0,
        ///SQ10 [15:19]
        ///10th conversion in regular
        ///sequence
        sq10: u5 = 0,
        ///SQ11 [20:24]
        ///11th conversion in regular
        ///sequence
        sq11: u5 = 0,
        ///SQ12 [25:29]
        ///12th conversion in regular
        ///sequence
        sq12: u5 = 0,
        _unused30: u2 = 0,
    };
    ///regular sequence register 2
    pub const sqr2 = Register(sqr2_val).init(0x40013C00 + 0x30);

    //////////////////////////
    ///SQR3
    const sqr3_val = packed struct {
        ///SQ1 [0:4]
        ///1st conversion in regular
        ///sequence
        sq1: u5 = 0,
        ///SQ2 [5:9]
        ///2nd conversion in regular
        ///sequence
        sq2: u5 = 0,
        ///SQ3 [10:14]
        ///3rd conversion in regular
        ///sequence
        sq3: u5 = 0,
        ///SQ4 [15:19]
        ///4th conversion in regular
        ///sequence
        sq4: u5 = 0,
        ///SQ5 [20:24]
        ///5th conversion in regular
        ///sequence
        sq5: u5 = 0,
        ///SQ6 [25:29]
        ///6th conversion in regular
        ///sequence
        sq6: u5 = 0,
        _unused30: u2 = 0,
    };
    ///regular sequence register 3
    pub const sqr3 = Register(sqr3_val).init(0x40013C00 + 0x34);

    //////////////////////////
    ///JSQR
    const jsqr_val = packed struct {
        ///JSQ1 [0:4]
        ///1st conversion in injected
        ///sequence
        jsq1: u5 = 0,
        ///JSQ2 [5:9]
        ///2nd conversion in injected
        ///sequence
        jsq2: u5 = 0,
        ///JSQ3 [10:14]
        ///3rd conversion in injected
        ///sequence
        jsq3: u5 = 0,
        ///JSQ4 [15:19]
        ///4th conversion in injected
        ///sequence
        jsq4: u5 = 0,
        ///JL [20:21]
        ///Injected sequence length
        jl: u2 = 0,
        _unused22: u10 = 0,
    };
    ///injected sequence register
    pub const jsqr = Register(jsqr_val).init(0x40013C00 + 0x38);

    //////////////////////////
    ///JDR1
    const jdr1_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr1 = RegisterRW(jdr1_val, void).init(0x40013C00 + 0x3C);

    //////////////////////////
    ///JDR2
    const jdr2_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr2 = RegisterRW(jdr2_val, void).init(0x40013C00 + 0x40);

    //////////////////////////
    ///JDR3
    const jdr3_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr3 = RegisterRW(jdr3_val, void).init(0x40013C00 + 0x44);

    //////////////////////////
    ///JDR4
    const jdr4_val = packed struct {
        ///JDATA [0:15]
        ///Injected data
        jdata: u16 = 0,
        _unused16: u16 = 0,
    };
    ///injected data register x
    pub const jdr4 = RegisterRW(jdr4_val, void).init(0x40013C00 + 0x48);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DATA [0:15]
        ///Regular data
        data: u16 = 0,
        _unused16: u16 = 0,
    };
    ///regular data register
    pub const dr = RegisterRW(dr_val, void).init(0x40013C00 + 0x4C);
};

///Controller area network
pub const can1 = struct {

    //////////////////////////
    ///CAN_MCR
    const can_mcr_val = packed struct {
        ///INRQ [0:0]
        ///INRQ
        inrq: u1 = 0,
        ///SLEEP [1:1]
        ///SLEEP
        sleep: u1 = 0,
        ///TXFP [2:2]
        ///TXFP
        txfp: u1 = 0,
        ///RFLM [3:3]
        ///RFLM
        rflm: u1 = 0,
        ///NART [4:4]
        ///NART
        nart: u1 = 0,
        ///AWUM [5:5]
        ///AWUM
        awum: u1 = 0,
        ///ABOM [6:6]
        ///ABOM
        abom: u1 = 0,
        ///TTCM [7:7]
        ///TTCM
        ttcm: u1 = 0,
        _unused8: u7 = 0,
        ///RESET [15:15]
        ///RESET
        reset: u1 = 0,
        ///DBF [16:16]
        ///DBF
        dbf: u1 = 0,
        _unused17: u15 = 0,
    };
    ///CAN_MCR
    pub const can_mcr = Register(can_mcr_val).init(0x40006400 + 0x0);

    //////////////////////////
    ///CAN_MSR
    const can_msr_val = packed struct {
        ///INAK [0:0]
        ///INAK
        inak: u1 = 0,
        ///SLAK [1:1]
        ///SLAK
        slak: u1 = 0,
        ///ERRI [2:2]
        ///ERRI
        erri: u1 = 0,
        ///WKUI [3:3]
        ///WKUI
        wkui: u1 = 0,
        ///SLAKI [4:4]
        ///SLAKI
        slaki: u1 = 0,
        _unused5: u3 = 0,
        ///TXM [8:8]
        ///TXM
        txm: u1 = 0,
        ///RXM [9:9]
        ///RXM
        rxm: u1 = 0,
        ///SAMP [10:10]
        ///SAMP
        samp: u1 = 0,
        ///RX [11:11]
        ///RX
        rx: u1 = 0,
        _unused12: u20 = 0,
    };
    ///CAN_MSR
    pub const can_msr = Register(can_msr_val).init(0x40006400 + 0x4);

    //////////////////////////
    ///CAN_TSR
    const can_tsr_val = packed struct {
        ///RQCP0 [0:0]
        ///RQCP0
        rqcp0: u1 = 0,
        ///TXOK0 [1:1]
        ///TXOK0
        txok0: u1 = 0,
        ///ALST0 [2:2]
        ///ALST0
        alst0: u1 = 0,
        ///TERR0 [3:3]
        ///TERR0
        terr0: u1 = 0,
        _unused4: u3 = 0,
        ///ABRQ0 [7:7]
        ///ABRQ0
        abrq0: u1 = 0,
        ///RQCP1 [8:8]
        ///RQCP1
        rqcp1: u1 = 0,
        ///TXOK1 [9:9]
        ///TXOK1
        txok1: u1 = 0,
        ///ALST1 [10:10]
        ///ALST1
        alst1: u1 = 0,
        ///TERR1 [11:11]
        ///TERR1
        terr1: u1 = 0,
        _unused12: u3 = 0,
        ///ABRQ1 [15:15]
        ///ABRQ1
        abrq1: u1 = 0,
        ///RQCP2 [16:16]
        ///RQCP2
        rqcp2: u1 = 0,
        ///TXOK2 [17:17]
        ///TXOK2
        txok2: u1 = 0,
        ///ALST2 [18:18]
        ///ALST2
        alst2: u1 = 0,
        ///TERR2 [19:19]
        ///TERR2
        terr2: u1 = 0,
        _unused20: u3 = 0,
        ///ABRQ2 [23:23]
        ///ABRQ2
        abrq2: u1 = 0,
        ///CODE [24:25]
        ///CODE
        code: u2 = 0,
        ///TME0 [26:26]
        ///Lowest priority flag for mailbox
        ///0
        tme0: u1 = 0,
        ///TME1 [27:27]
        ///Lowest priority flag for mailbox
        ///1
        tme1: u1 = 0,
        ///TME2 [28:28]
        ///Lowest priority flag for mailbox
        ///2
        tme2: u1 = 0,
        ///LOW0 [29:29]
        ///Lowest priority flag for mailbox
        ///0
        low0: u1 = 0,
        ///LOW1 [30:30]
        ///Lowest priority flag for mailbox
        ///1
        low1: u1 = 0,
        ///LOW2 [31:31]
        ///Lowest priority flag for mailbox
        ///2
        low2: u1 = 0,
    };
    ///CAN_TSR
    pub const can_tsr = Register(can_tsr_val).init(0x40006400 + 0x8);

    //////////////////////////
    ///CAN_RF0R
    const can_rf0r_val = packed struct {
        ///FMP0 [0:1]
        ///FMP0
        fmp0: u2 = 0,
        _unused2: u1 = 0,
        ///FULL0 [3:3]
        ///FULL0
        full0: u1 = 0,
        ///FOVR0 [4:4]
        ///FOVR0
        fovr0: u1 = 0,
        ///RFOM0 [5:5]
        ///RFOM0
        rfom0: u1 = 0,
        _unused6: u26 = 0,
    };
    ///CAN_RF0R
    pub const can_rf0r = Register(can_rf0r_val).init(0x40006400 + 0xC);

    //////////////////////////
    ///CAN_RF1R
    const can_rf1r_val = packed struct {
        ///FMP1 [0:1]
        ///FMP1
        fmp1: u2 = 0,
        _unused2: u1 = 0,
        ///FULL1 [3:3]
        ///FULL1
        full1: u1 = 0,
        ///FOVR1 [4:4]
        ///FOVR1
        fovr1: u1 = 0,
        ///RFOM1 [5:5]
        ///RFOM1
        rfom1: u1 = 0,
        _unused6: u26 = 0,
    };
    ///CAN_RF1R
    pub const can_rf1r = Register(can_rf1r_val).init(0x40006400 + 0x10);

    //////////////////////////
    ///CAN_IER
    const can_ier_val = packed struct {
        ///TMEIE [0:0]
        ///TMEIE
        tmeie: u1 = 0,
        ///FMPIE0 [1:1]
        ///FMPIE0
        fmpie0: u1 = 0,
        ///FFIE0 [2:2]
        ///FFIE0
        ffie0: u1 = 0,
        ///FOVIE0 [3:3]
        ///FOVIE0
        fovie0: u1 = 0,
        ///FMPIE1 [4:4]
        ///FMPIE1
        fmpie1: u1 = 0,
        ///FFIE1 [5:5]
        ///FFIE1
        ffie1: u1 = 0,
        ///FOVIE1 [6:6]
        ///FOVIE1
        fovie1: u1 = 0,
        _unused7: u1 = 0,
        ///EWGIE [8:8]
        ///EWGIE
        ewgie: u1 = 0,
        ///EPVIE [9:9]
        ///EPVIE
        epvie: u1 = 0,
        ///BOFIE [10:10]
        ///BOFIE
        bofie: u1 = 0,
        ///LECIE [11:11]
        ///LECIE
        lecie: u1 = 0,
        _unused12: u3 = 0,
        ///ERRIE [15:15]
        ///ERRIE
        errie: u1 = 0,
        ///WKUIE [16:16]
        ///WKUIE
        wkuie: u1 = 0,
        ///SLKIE [17:17]
        ///SLKIE
        slkie: u1 = 0,
        _unused18: u14 = 0,
    };
    ///CAN_IER
    pub const can_ier = Register(can_ier_val).init(0x40006400 + 0x14);

    //////////////////////////
    ///CAN_ESR
    const can_esr_val = packed struct {
        ///EWGF [0:0]
        ///EWGF
        ewgf: u1 = 0,
        ///EPVF [1:1]
        ///EPVF
        epvf: u1 = 0,
        ///BOFF [2:2]
        ///BOFF
        boff: u1 = 0,
        _unused3: u1 = 0,
        ///LEC [4:6]
        ///LEC
        lec: u3 = 0,
        _unused7: u9 = 0,
        ///TEC [16:23]
        ///TEC
        tec: u8 = 0,
        ///REC [24:31]
        ///REC
        rec: u8 = 0,
    };
    ///CAN_ESR
    pub const can_esr = Register(can_esr_val).init(0x40006400 + 0x18);

    //////////////////////////
    ///CAN_BTR
    const can_btr_val = packed struct {
        ///BRP [0:9]
        ///BRP
        brp: u10 = 0,
        _unused10: u6 = 0,
        ///TS1 [16:19]
        ///TS1
        ts1: u4 = 0,
        ///TS2 [20:22]
        ///TS2
        ts2: u3 = 0,
        _unused23: u1 = 0,
        ///SJW [24:25]
        ///SJW
        sjw: u2 = 0,
        _unused26: u4 = 0,
        ///LBKM [30:30]
        ///LBKM
        lbkm: u1 = 0,
        ///SILM [31:31]
        ///SILM
        silm: u1 = 0,
    };
    ///CAN_BTR
    pub const can_btr = Register(can_btr_val).init(0x40006400 + 0x1C);

    //////////////////////////
    ///CAN_TI0R
    const can_ti0r_val = packed struct {
        ///TXRQ [0:0]
        ///TXRQ
        txrq: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_TI0R
    pub const can_ti0r = Register(can_ti0r_val).init(0x40006400 + 0x180);

    //////////////////////////
    ///CAN_TDT0R
    const can_tdt0r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///TGT [8:8]
        ///TGT
        tgt: u1 = 0,
        _unused9: u7 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_TDT0R
    pub const can_tdt0r = Register(can_tdt0r_val).init(0x40006400 + 0x184);

    //////////////////////////
    ///CAN_TDL0R
    const can_tdl0r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_TDL0R
    pub const can_tdl0r = Register(can_tdl0r_val).init(0x40006400 + 0x188);

    //////////////////////////
    ///CAN_TDH0R
    const can_tdh0r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_TDH0R
    pub const can_tdh0r = Register(can_tdh0r_val).init(0x40006400 + 0x18C);

    //////////////////////////
    ///CAN_TI1R
    const can_ti1r_val = packed struct {
        ///TXRQ [0:0]
        ///TXRQ
        txrq: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_TI1R
    pub const can_ti1r = Register(can_ti1r_val).init(0x40006400 + 0x190);

    //////////////////////////
    ///CAN_TDT1R
    const can_tdt1r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///TGT [8:8]
        ///TGT
        tgt: u1 = 0,
        _unused9: u7 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_TDT1R
    pub const can_tdt1r = Register(can_tdt1r_val).init(0x40006400 + 0x194);

    //////////////////////////
    ///CAN_TDL1R
    const can_tdl1r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_TDL1R
    pub const can_tdl1r = Register(can_tdl1r_val).init(0x40006400 + 0x198);

    //////////////////////////
    ///CAN_TDH1R
    const can_tdh1r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_TDH1R
    pub const can_tdh1r = Register(can_tdh1r_val).init(0x40006400 + 0x19C);

    //////////////////////////
    ///CAN_TI2R
    const can_ti2r_val = packed struct {
        ///TXRQ [0:0]
        ///TXRQ
        txrq: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_TI2R
    pub const can_ti2r = Register(can_ti2r_val).init(0x40006400 + 0x1A0);

    //////////////////////////
    ///CAN_TDT2R
    const can_tdt2r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///TGT [8:8]
        ///TGT
        tgt: u1 = 0,
        _unused9: u7 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_TDT2R
    pub const can_tdt2r = Register(can_tdt2r_val).init(0x40006400 + 0x1A4);

    //////////////////////////
    ///CAN_TDL2R
    const can_tdl2r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_TDL2R
    pub const can_tdl2r = Register(can_tdl2r_val).init(0x40006400 + 0x1A8);

    //////////////////////////
    ///CAN_TDH2R
    const can_tdh2r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_TDH2R
    pub const can_tdh2r = Register(can_tdh2r_val).init(0x40006400 + 0x1AC);

    //////////////////////////
    ///CAN_RI0R
    const can_ri0r_val = packed struct {
        _unused0: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_RI0R
    pub const can_ri0r = RegisterRW(can_ri0r_val, void).init(0x40006400 + 0x1B0);

    //////////////////////////
    ///CAN_RDT0R
    const can_rdt0r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///FMI [8:15]
        ///FMI
        fmi: u8 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_RDT0R
    pub const can_rdt0r = RegisterRW(can_rdt0r_val, void).init(0x40006400 + 0x1B4);

    //////////////////////////
    ///CAN_RDL0R
    const can_rdl0r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_RDL0R
    pub const can_rdl0r = RegisterRW(can_rdl0r_val, void).init(0x40006400 + 0x1B8);

    //////////////////////////
    ///CAN_RDH0R
    const can_rdh0r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_RDH0R
    pub const can_rdh0r = RegisterRW(can_rdh0r_val, void).init(0x40006400 + 0x1BC);

    //////////////////////////
    ///CAN_RI1R
    const can_ri1r_val = packed struct {
        _unused0: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_RI1R
    pub const can_ri1r = RegisterRW(can_ri1r_val, void).init(0x40006400 + 0x1C0);

    //////////////////////////
    ///CAN_RDT1R
    const can_rdt1r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///FMI [8:15]
        ///FMI
        fmi: u8 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_RDT1R
    pub const can_rdt1r = RegisterRW(can_rdt1r_val, void).init(0x40006400 + 0x1C4);

    //////////////////////////
    ///CAN_RDL1R
    const can_rdl1r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_RDL1R
    pub const can_rdl1r = RegisterRW(can_rdl1r_val, void).init(0x40006400 + 0x1C8);

    //////////////////////////
    ///CAN_RDH1R
    const can_rdh1r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_RDH1R
    pub const can_rdh1r = RegisterRW(can_rdh1r_val, void).init(0x40006400 + 0x1CC);

    //////////////////////////
    ///CAN_FMR
    const can_fmr_val = packed struct {
        ///FINIT [0:0]
        ///FINIT
        finit: u1 = 0,
        _unused1: u31 = 0,
    };
    ///CAN_FMR
    pub const can_fmr = Register(can_fmr_val).init(0x40006400 + 0x200);

    //////////////////////////
    ///CAN_FM1R
    const can_fm1r_val = packed struct {
        ///FBM0 [0:0]
        ///Filter mode
        fbm0: u1 = 0,
        ///FBM1 [1:1]
        ///Filter mode
        fbm1: u1 = 0,
        ///FBM2 [2:2]
        ///Filter mode
        fbm2: u1 = 0,
        ///FBM3 [3:3]
        ///Filter mode
        fbm3: u1 = 0,
        ///FBM4 [4:4]
        ///Filter mode
        fbm4: u1 = 0,
        ///FBM5 [5:5]
        ///Filter mode
        fbm5: u1 = 0,
        ///FBM6 [6:6]
        ///Filter mode
        fbm6: u1 = 0,
        ///FBM7 [7:7]
        ///Filter mode
        fbm7: u1 = 0,
        ///FBM8 [8:8]
        ///Filter mode
        fbm8: u1 = 0,
        ///FBM9 [9:9]
        ///Filter mode
        fbm9: u1 = 0,
        ///FBM10 [10:10]
        ///Filter mode
        fbm10: u1 = 0,
        ///FBM11 [11:11]
        ///Filter mode
        fbm11: u1 = 0,
        ///FBM12 [12:12]
        ///Filter mode
        fbm12: u1 = 0,
        ///FBM13 [13:13]
        ///Filter mode
        fbm13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FM1R
    pub const can_fm1r = Register(can_fm1r_val).init(0x40006400 + 0x204);

    //////////////////////////
    ///CAN_FS1R
    const can_fs1r_val = packed struct {
        ///FSC0 [0:0]
        ///Filter scale configuration
        fsc0: u1 = 0,
        ///FSC1 [1:1]
        ///Filter scale configuration
        fsc1: u1 = 0,
        ///FSC2 [2:2]
        ///Filter scale configuration
        fsc2: u1 = 0,
        ///FSC3 [3:3]
        ///Filter scale configuration
        fsc3: u1 = 0,
        ///FSC4 [4:4]
        ///Filter scale configuration
        fsc4: u1 = 0,
        ///FSC5 [5:5]
        ///Filter scale configuration
        fsc5: u1 = 0,
        ///FSC6 [6:6]
        ///Filter scale configuration
        fsc6: u1 = 0,
        ///FSC7 [7:7]
        ///Filter scale configuration
        fsc7: u1 = 0,
        ///FSC8 [8:8]
        ///Filter scale configuration
        fsc8: u1 = 0,
        ///FSC9 [9:9]
        ///Filter scale configuration
        fsc9: u1 = 0,
        ///FSC10 [10:10]
        ///Filter scale configuration
        fsc10: u1 = 0,
        ///FSC11 [11:11]
        ///Filter scale configuration
        fsc11: u1 = 0,
        ///FSC12 [12:12]
        ///Filter scale configuration
        fsc12: u1 = 0,
        ///FSC13 [13:13]
        ///Filter scale configuration
        fsc13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FS1R
    pub const can_fs1r = Register(can_fs1r_val).init(0x40006400 + 0x20C);

    //////////////////////////
    ///CAN_FFA1R
    const can_ffa1r_val = packed struct {
        ///FFA0 [0:0]
        ///Filter FIFO assignment for filter
        ///0
        ffa0: u1 = 0,
        ///FFA1 [1:1]
        ///Filter FIFO assignment for filter
        ///1
        ffa1: u1 = 0,
        ///FFA2 [2:2]
        ///Filter FIFO assignment for filter
        ///2
        ffa2: u1 = 0,
        ///FFA3 [3:3]
        ///Filter FIFO assignment for filter
        ///3
        ffa3: u1 = 0,
        ///FFA4 [4:4]
        ///Filter FIFO assignment for filter
        ///4
        ffa4: u1 = 0,
        ///FFA5 [5:5]
        ///Filter FIFO assignment for filter
        ///5
        ffa5: u1 = 0,
        ///FFA6 [6:6]
        ///Filter FIFO assignment for filter
        ///6
        ffa6: u1 = 0,
        ///FFA7 [7:7]
        ///Filter FIFO assignment for filter
        ///7
        ffa7: u1 = 0,
        ///FFA8 [8:8]
        ///Filter FIFO assignment for filter
        ///8
        ffa8: u1 = 0,
        ///FFA9 [9:9]
        ///Filter FIFO assignment for filter
        ///9
        ffa9: u1 = 0,
        ///FFA10 [10:10]
        ///Filter FIFO assignment for filter
        ///10
        ffa10: u1 = 0,
        ///FFA11 [11:11]
        ///Filter FIFO assignment for filter
        ///11
        ffa11: u1 = 0,
        ///FFA12 [12:12]
        ///Filter FIFO assignment for filter
        ///12
        ffa12: u1 = 0,
        ///FFA13 [13:13]
        ///Filter FIFO assignment for filter
        ///13
        ffa13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FFA1R
    pub const can_ffa1r = Register(can_ffa1r_val).init(0x40006400 + 0x214);

    //////////////////////////
    ///CAN_FA1R
    const can_fa1r_val = packed struct {
        ///FACT0 [0:0]
        ///Filter active
        fact0: u1 = 0,
        ///FACT1 [1:1]
        ///Filter active
        fact1: u1 = 0,
        ///FACT2 [2:2]
        ///Filter active
        fact2: u1 = 0,
        ///FACT3 [3:3]
        ///Filter active
        fact3: u1 = 0,
        ///FACT4 [4:4]
        ///Filter active
        fact4: u1 = 0,
        ///FACT5 [5:5]
        ///Filter active
        fact5: u1 = 0,
        ///FACT6 [6:6]
        ///Filter active
        fact6: u1 = 0,
        ///FACT7 [7:7]
        ///Filter active
        fact7: u1 = 0,
        ///FACT8 [8:8]
        ///Filter active
        fact8: u1 = 0,
        ///FACT9 [9:9]
        ///Filter active
        fact9: u1 = 0,
        ///FACT10 [10:10]
        ///Filter active
        fact10: u1 = 0,
        ///FACT11 [11:11]
        ///Filter active
        fact11: u1 = 0,
        ///FACT12 [12:12]
        ///Filter active
        fact12: u1 = 0,
        ///FACT13 [13:13]
        ///Filter active
        fact13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FA1R
    pub const can_fa1r = Register(can_fa1r_val).init(0x40006400 + 0x21C);

    //////////////////////////
    ///F0R1
    const f0r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 0 register 1
    pub const f0r1 = Register(f0r1_val).init(0x40006400 + 0x240);

    //////////////////////////
    ///F0R2
    const f0r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 0 register 2
    pub const f0r2 = Register(f0r2_val).init(0x40006400 + 0x244);

    //////////////////////////
    ///F1R1
    const f1r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 1 register 1
    pub const f1r1 = Register(f1r1_val).init(0x40006400 + 0x248);

    //////////////////////////
    ///F1R2
    const f1r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 1 register 2
    pub const f1r2 = Register(f1r2_val).init(0x40006400 + 0x24C);

    //////////////////////////
    ///F2R1
    const f2r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 2 register 1
    pub const f2r1 = Register(f2r1_val).init(0x40006400 + 0x250);

    //////////////////////////
    ///F2R2
    const f2r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 2 register 2
    pub const f2r2 = Register(f2r2_val).init(0x40006400 + 0x254);

    //////////////////////////
    ///F3R1
    const f3r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 3 register 1
    pub const f3r1 = Register(f3r1_val).init(0x40006400 + 0x258);

    //////////////////////////
    ///F3R2
    const f3r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 3 register 2
    pub const f3r2 = Register(f3r2_val).init(0x40006400 + 0x25C);

    //////////////////////////
    ///F4R1
    const f4r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 4 register 1
    pub const f4r1 = Register(f4r1_val).init(0x40006400 + 0x260);

    //////////////////////////
    ///F4R2
    const f4r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 4 register 2
    pub const f4r2 = Register(f4r2_val).init(0x40006400 + 0x264);

    //////////////////////////
    ///F5R1
    const f5r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 5 register 1
    pub const f5r1 = Register(f5r1_val).init(0x40006400 + 0x268);

    //////////////////////////
    ///F5R2
    const f5r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 5 register 2
    pub const f5r2 = Register(f5r2_val).init(0x40006400 + 0x26C);

    //////////////////////////
    ///F6R1
    const f6r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 6 register 1
    pub const f6r1 = Register(f6r1_val).init(0x40006400 + 0x270);

    //////////////////////////
    ///F6R2
    const f6r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 6 register 2
    pub const f6r2 = Register(f6r2_val).init(0x40006400 + 0x274);

    //////////////////////////
    ///F7R1
    const f7r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 7 register 1
    pub const f7r1 = Register(f7r1_val).init(0x40006400 + 0x278);

    //////////////////////////
    ///F7R2
    const f7r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 7 register 2
    pub const f7r2 = Register(f7r2_val).init(0x40006400 + 0x27C);

    //////////////////////////
    ///F8R1
    const f8r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 8 register 1
    pub const f8r1 = Register(f8r1_val).init(0x40006400 + 0x280);

    //////////////////////////
    ///F8R2
    const f8r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 8 register 2
    pub const f8r2 = Register(f8r2_val).init(0x40006400 + 0x284);

    //////////////////////////
    ///F9R1
    const f9r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 9 register 1
    pub const f9r1 = Register(f9r1_val).init(0x40006400 + 0x288);

    //////////////////////////
    ///F9R2
    const f9r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 9 register 2
    pub const f9r2 = Register(f9r2_val).init(0x40006400 + 0x28C);

    //////////////////////////
    ///F10R1
    const f10r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 10 register 1
    pub const f10r1 = Register(f10r1_val).init(0x40006400 + 0x290);

    //////////////////////////
    ///F10R2
    const f10r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 10 register 2
    pub const f10r2 = Register(f10r2_val).init(0x40006400 + 0x294);

    //////////////////////////
    ///F11R1
    const f11r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 11 register 1
    pub const f11r1 = Register(f11r1_val).init(0x40006400 + 0x298);

    //////////////////////////
    ///F11R2
    const f11r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 11 register 2
    pub const f11r2 = Register(f11r2_val).init(0x40006400 + 0x29C);

    //////////////////////////
    ///F12R1
    const f12r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 4 register 1
    pub const f12r1 = Register(f12r1_val).init(0x40006400 + 0x2A0);

    //////////////////////////
    ///F12R2
    const f12r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 12 register 2
    pub const f12r2 = Register(f12r2_val).init(0x40006400 + 0x2A4);

    //////////////////////////
    ///F13R1
    const f13r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 13 register 1
    pub const f13r1 = Register(f13r1_val).init(0x40006400 + 0x2A8);

    //////////////////////////
    ///F13R2
    const f13r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 13 register 2
    pub const f13r2 = Register(f13r2_val).init(0x40006400 + 0x2AC);
};

///Controller area network
pub const can2 = struct {

    //////////////////////////
    ///CAN_MCR
    const can_mcr_val = packed struct {
        ///INRQ [0:0]
        ///INRQ
        inrq: u1 = 0,
        ///SLEEP [1:1]
        ///SLEEP
        sleep: u1 = 0,
        ///TXFP [2:2]
        ///TXFP
        txfp: u1 = 0,
        ///RFLM [3:3]
        ///RFLM
        rflm: u1 = 0,
        ///NART [4:4]
        ///NART
        nart: u1 = 0,
        ///AWUM [5:5]
        ///AWUM
        awum: u1 = 0,
        ///ABOM [6:6]
        ///ABOM
        abom: u1 = 0,
        ///TTCM [7:7]
        ///TTCM
        ttcm: u1 = 0,
        _unused8: u7 = 0,
        ///RESET [15:15]
        ///RESET
        reset: u1 = 0,
        ///DBF [16:16]
        ///DBF
        dbf: u1 = 0,
        _unused17: u15 = 0,
    };
    ///CAN_MCR
    pub const can_mcr = Register(can_mcr_val).init(0x40006800 + 0x0);

    //////////////////////////
    ///CAN_MSR
    const can_msr_val = packed struct {
        ///INAK [0:0]
        ///INAK
        inak: u1 = 0,
        ///SLAK [1:1]
        ///SLAK
        slak: u1 = 0,
        ///ERRI [2:2]
        ///ERRI
        erri: u1 = 0,
        ///WKUI [3:3]
        ///WKUI
        wkui: u1 = 0,
        ///SLAKI [4:4]
        ///SLAKI
        slaki: u1 = 0,
        _unused5: u3 = 0,
        ///TXM [8:8]
        ///TXM
        txm: u1 = 0,
        ///RXM [9:9]
        ///RXM
        rxm: u1 = 0,
        ///SAMP [10:10]
        ///SAMP
        samp: u1 = 0,
        ///RX [11:11]
        ///RX
        rx: u1 = 0,
        _unused12: u20 = 0,
    };
    ///CAN_MSR
    pub const can_msr = Register(can_msr_val).init(0x40006800 + 0x4);

    //////////////////////////
    ///CAN_TSR
    const can_tsr_val = packed struct {
        ///RQCP0 [0:0]
        ///RQCP0
        rqcp0: u1 = 0,
        ///TXOK0 [1:1]
        ///TXOK0
        txok0: u1 = 0,
        ///ALST0 [2:2]
        ///ALST0
        alst0: u1 = 0,
        ///TERR0 [3:3]
        ///TERR0
        terr0: u1 = 0,
        _unused4: u3 = 0,
        ///ABRQ0 [7:7]
        ///ABRQ0
        abrq0: u1 = 0,
        ///RQCP1 [8:8]
        ///RQCP1
        rqcp1: u1 = 0,
        ///TXOK1 [9:9]
        ///TXOK1
        txok1: u1 = 0,
        ///ALST1 [10:10]
        ///ALST1
        alst1: u1 = 0,
        ///TERR1 [11:11]
        ///TERR1
        terr1: u1 = 0,
        _unused12: u3 = 0,
        ///ABRQ1 [15:15]
        ///ABRQ1
        abrq1: u1 = 0,
        ///RQCP2 [16:16]
        ///RQCP2
        rqcp2: u1 = 0,
        ///TXOK2 [17:17]
        ///TXOK2
        txok2: u1 = 0,
        ///ALST2 [18:18]
        ///ALST2
        alst2: u1 = 0,
        ///TERR2 [19:19]
        ///TERR2
        terr2: u1 = 0,
        _unused20: u3 = 0,
        ///ABRQ2 [23:23]
        ///ABRQ2
        abrq2: u1 = 0,
        ///CODE [24:25]
        ///CODE
        code: u2 = 0,
        ///TME0 [26:26]
        ///Lowest priority flag for mailbox
        ///0
        tme0: u1 = 0,
        ///TME1 [27:27]
        ///Lowest priority flag for mailbox
        ///1
        tme1: u1 = 0,
        ///TME2 [28:28]
        ///Lowest priority flag for mailbox
        ///2
        tme2: u1 = 0,
        ///LOW0 [29:29]
        ///Lowest priority flag for mailbox
        ///0
        low0: u1 = 0,
        ///LOW1 [30:30]
        ///Lowest priority flag for mailbox
        ///1
        low1: u1 = 0,
        ///LOW2 [31:31]
        ///Lowest priority flag for mailbox
        ///2
        low2: u1 = 0,
    };
    ///CAN_TSR
    pub const can_tsr = Register(can_tsr_val).init(0x40006800 + 0x8);

    //////////////////////////
    ///CAN_RF0R
    const can_rf0r_val = packed struct {
        ///FMP0 [0:1]
        ///FMP0
        fmp0: u2 = 0,
        _unused2: u1 = 0,
        ///FULL0 [3:3]
        ///FULL0
        full0: u1 = 0,
        ///FOVR0 [4:4]
        ///FOVR0
        fovr0: u1 = 0,
        ///RFOM0 [5:5]
        ///RFOM0
        rfom0: u1 = 0,
        _unused6: u26 = 0,
    };
    ///CAN_RF0R
    pub const can_rf0r = Register(can_rf0r_val).init(0x40006800 + 0xC);

    //////////////////////////
    ///CAN_RF1R
    const can_rf1r_val = packed struct {
        ///FMP1 [0:1]
        ///FMP1
        fmp1: u2 = 0,
        _unused2: u1 = 0,
        ///FULL1 [3:3]
        ///FULL1
        full1: u1 = 0,
        ///FOVR1 [4:4]
        ///FOVR1
        fovr1: u1 = 0,
        ///RFOM1 [5:5]
        ///RFOM1
        rfom1: u1 = 0,
        _unused6: u26 = 0,
    };
    ///CAN_RF1R
    pub const can_rf1r = Register(can_rf1r_val).init(0x40006800 + 0x10);

    //////////////////////////
    ///CAN_IER
    const can_ier_val = packed struct {
        ///TMEIE [0:0]
        ///TMEIE
        tmeie: u1 = 0,
        ///FMPIE0 [1:1]
        ///FMPIE0
        fmpie0: u1 = 0,
        ///FFIE0 [2:2]
        ///FFIE0
        ffie0: u1 = 0,
        ///FOVIE0 [3:3]
        ///FOVIE0
        fovie0: u1 = 0,
        ///FMPIE1 [4:4]
        ///FMPIE1
        fmpie1: u1 = 0,
        ///FFIE1 [5:5]
        ///FFIE1
        ffie1: u1 = 0,
        ///FOVIE1 [6:6]
        ///FOVIE1
        fovie1: u1 = 0,
        _unused7: u1 = 0,
        ///EWGIE [8:8]
        ///EWGIE
        ewgie: u1 = 0,
        ///EPVIE [9:9]
        ///EPVIE
        epvie: u1 = 0,
        ///BOFIE [10:10]
        ///BOFIE
        bofie: u1 = 0,
        ///LECIE [11:11]
        ///LECIE
        lecie: u1 = 0,
        _unused12: u3 = 0,
        ///ERRIE [15:15]
        ///ERRIE
        errie: u1 = 0,
        ///WKUIE [16:16]
        ///WKUIE
        wkuie: u1 = 0,
        ///SLKIE [17:17]
        ///SLKIE
        slkie: u1 = 0,
        _unused18: u14 = 0,
    };
    ///CAN_IER
    pub const can_ier = Register(can_ier_val).init(0x40006800 + 0x14);

    //////////////////////////
    ///CAN_ESR
    const can_esr_val = packed struct {
        ///EWGF [0:0]
        ///EWGF
        ewgf: u1 = 0,
        ///EPVF [1:1]
        ///EPVF
        epvf: u1 = 0,
        ///BOFF [2:2]
        ///BOFF
        boff: u1 = 0,
        _unused3: u1 = 0,
        ///LEC [4:6]
        ///LEC
        lec: u3 = 0,
        _unused7: u9 = 0,
        ///TEC [16:23]
        ///TEC
        tec: u8 = 0,
        ///REC [24:31]
        ///REC
        rec: u8 = 0,
    };
    ///CAN_ESR
    pub const can_esr = Register(can_esr_val).init(0x40006800 + 0x18);

    //////////////////////////
    ///CAN_BTR
    const can_btr_val = packed struct {
        ///BRP [0:9]
        ///BRP
        brp: u10 = 0,
        _unused10: u6 = 0,
        ///TS1 [16:19]
        ///TS1
        ts1: u4 = 0,
        ///TS2 [20:22]
        ///TS2
        ts2: u3 = 0,
        _unused23: u1 = 0,
        ///SJW [24:25]
        ///SJW
        sjw: u2 = 0,
        _unused26: u4 = 0,
        ///LBKM [30:30]
        ///LBKM
        lbkm: u1 = 0,
        ///SILM [31:31]
        ///SILM
        silm: u1 = 0,
    };
    ///CAN_BTR
    pub const can_btr = Register(can_btr_val).init(0x40006800 + 0x1C);

    //////////////////////////
    ///CAN_TI0R
    const can_ti0r_val = packed struct {
        ///TXRQ [0:0]
        ///TXRQ
        txrq: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_TI0R
    pub const can_ti0r = Register(can_ti0r_val).init(0x40006800 + 0x180);

    //////////////////////////
    ///CAN_TDT0R
    const can_tdt0r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///TGT [8:8]
        ///TGT
        tgt: u1 = 0,
        _unused9: u7 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_TDT0R
    pub const can_tdt0r = Register(can_tdt0r_val).init(0x40006800 + 0x184);

    //////////////////////////
    ///CAN_TDL0R
    const can_tdl0r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_TDL0R
    pub const can_tdl0r = Register(can_tdl0r_val).init(0x40006800 + 0x188);

    //////////////////////////
    ///CAN_TDH0R
    const can_tdh0r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_TDH0R
    pub const can_tdh0r = Register(can_tdh0r_val).init(0x40006800 + 0x18C);

    //////////////////////////
    ///CAN_TI1R
    const can_ti1r_val = packed struct {
        ///TXRQ [0:0]
        ///TXRQ
        txrq: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_TI1R
    pub const can_ti1r = Register(can_ti1r_val).init(0x40006800 + 0x190);

    //////////////////////////
    ///CAN_TDT1R
    const can_tdt1r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///TGT [8:8]
        ///TGT
        tgt: u1 = 0,
        _unused9: u7 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_TDT1R
    pub const can_tdt1r = Register(can_tdt1r_val).init(0x40006800 + 0x194);

    //////////////////////////
    ///CAN_TDL1R
    const can_tdl1r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_TDL1R
    pub const can_tdl1r = Register(can_tdl1r_val).init(0x40006800 + 0x198);

    //////////////////////////
    ///CAN_TDH1R
    const can_tdh1r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_TDH1R
    pub const can_tdh1r = Register(can_tdh1r_val).init(0x40006800 + 0x19C);

    //////////////////////////
    ///CAN_TI2R
    const can_ti2r_val = packed struct {
        ///TXRQ [0:0]
        ///TXRQ
        txrq: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_TI2R
    pub const can_ti2r = Register(can_ti2r_val).init(0x40006800 + 0x1A0);

    //////////////////////////
    ///CAN_TDT2R
    const can_tdt2r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///TGT [8:8]
        ///TGT
        tgt: u1 = 0,
        _unused9: u7 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_TDT2R
    pub const can_tdt2r = Register(can_tdt2r_val).init(0x40006800 + 0x1A4);

    //////////////////////////
    ///CAN_TDL2R
    const can_tdl2r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_TDL2R
    pub const can_tdl2r = Register(can_tdl2r_val).init(0x40006800 + 0x1A8);

    //////////////////////////
    ///CAN_TDH2R
    const can_tdh2r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_TDH2R
    pub const can_tdh2r = Register(can_tdh2r_val).init(0x40006800 + 0x1AC);

    //////////////////////////
    ///CAN_RI0R
    const can_ri0r_val = packed struct {
        _unused0: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_RI0R
    pub const can_ri0r = RegisterRW(can_ri0r_val, void).init(0x40006800 + 0x1B0);

    //////////////////////////
    ///CAN_RDT0R
    const can_rdt0r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///FMI [8:15]
        ///FMI
        fmi: u8 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_RDT0R
    pub const can_rdt0r = RegisterRW(can_rdt0r_val, void).init(0x40006800 + 0x1B4);

    //////////////////////////
    ///CAN_RDL0R
    const can_rdl0r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_RDL0R
    pub const can_rdl0r = RegisterRW(can_rdl0r_val, void).init(0x40006800 + 0x1B8);

    //////////////////////////
    ///CAN_RDH0R
    const can_rdh0r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_RDH0R
    pub const can_rdh0r = RegisterRW(can_rdh0r_val, void).init(0x40006800 + 0x1BC);

    //////////////////////////
    ///CAN_RI1R
    const can_ri1r_val = packed struct {
        _unused0: u1 = 0,
        ///RTR [1:1]
        ///RTR
        rtr: u1 = 0,
        ///IDE [2:2]
        ///IDE
        ide: u1 = 0,
        ///EXID [3:20]
        ///EXID
        exid: u18 = 0,
        ///STID [21:31]
        ///STID
        stid: u11 = 0,
    };
    ///CAN_RI1R
    pub const can_ri1r = RegisterRW(can_ri1r_val, void).init(0x40006800 + 0x1C0);

    //////////////////////////
    ///CAN_RDT1R
    const can_rdt1r_val = packed struct {
        ///DLC [0:3]
        ///DLC
        dlc: u4 = 0,
        _unused4: u4 = 0,
        ///FMI [8:15]
        ///FMI
        fmi: u8 = 0,
        ///TIME [16:31]
        ///TIME
        time: u16 = 0,
    };
    ///CAN_RDT1R
    pub const can_rdt1r = RegisterRW(can_rdt1r_val, void).init(0x40006800 + 0x1C4);

    //////////////////////////
    ///CAN_RDL1R
    const can_rdl1r_val = packed struct {
        ///DATA0 [0:7]
        ///DATA0
        data0: u8 = 0,
        ///DATA1 [8:15]
        ///DATA1
        data1: u8 = 0,
        ///DATA2 [16:23]
        ///DATA2
        data2: u8 = 0,
        ///DATA3 [24:31]
        ///DATA3
        data3: u8 = 0,
    };
    ///CAN_RDL1R
    pub const can_rdl1r = RegisterRW(can_rdl1r_val, void).init(0x40006800 + 0x1C8);

    //////////////////////////
    ///CAN_RDH1R
    const can_rdh1r_val = packed struct {
        ///DATA4 [0:7]
        ///DATA4
        data4: u8 = 0,
        ///DATA5 [8:15]
        ///DATA5
        data5: u8 = 0,
        ///DATA6 [16:23]
        ///DATA6
        data6: u8 = 0,
        ///DATA7 [24:31]
        ///DATA7
        data7: u8 = 0,
    };
    ///CAN_RDH1R
    pub const can_rdh1r = RegisterRW(can_rdh1r_val, void).init(0x40006800 + 0x1CC);

    //////////////////////////
    ///CAN_FMR
    const can_fmr_val = packed struct {
        ///FINIT [0:0]
        ///FINIT
        finit: u1 = 0,
        _unused1: u31 = 0,
    };
    ///CAN_FMR
    pub const can_fmr = Register(can_fmr_val).init(0x40006800 + 0x200);

    //////////////////////////
    ///CAN_FM1R
    const can_fm1r_val = packed struct {
        ///FBM0 [0:0]
        ///Filter mode
        fbm0: u1 = 0,
        ///FBM1 [1:1]
        ///Filter mode
        fbm1: u1 = 0,
        ///FBM2 [2:2]
        ///Filter mode
        fbm2: u1 = 0,
        ///FBM3 [3:3]
        ///Filter mode
        fbm3: u1 = 0,
        ///FBM4 [4:4]
        ///Filter mode
        fbm4: u1 = 0,
        ///FBM5 [5:5]
        ///Filter mode
        fbm5: u1 = 0,
        ///FBM6 [6:6]
        ///Filter mode
        fbm6: u1 = 0,
        ///FBM7 [7:7]
        ///Filter mode
        fbm7: u1 = 0,
        ///FBM8 [8:8]
        ///Filter mode
        fbm8: u1 = 0,
        ///FBM9 [9:9]
        ///Filter mode
        fbm9: u1 = 0,
        ///FBM10 [10:10]
        ///Filter mode
        fbm10: u1 = 0,
        ///FBM11 [11:11]
        ///Filter mode
        fbm11: u1 = 0,
        ///FBM12 [12:12]
        ///Filter mode
        fbm12: u1 = 0,
        ///FBM13 [13:13]
        ///Filter mode
        fbm13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FM1R
    pub const can_fm1r = Register(can_fm1r_val).init(0x40006800 + 0x204);

    //////////////////////////
    ///CAN_FS1R
    const can_fs1r_val = packed struct {
        ///FSC0 [0:0]
        ///Filter scale configuration
        fsc0: u1 = 0,
        ///FSC1 [1:1]
        ///Filter scale configuration
        fsc1: u1 = 0,
        ///FSC2 [2:2]
        ///Filter scale configuration
        fsc2: u1 = 0,
        ///FSC3 [3:3]
        ///Filter scale configuration
        fsc3: u1 = 0,
        ///FSC4 [4:4]
        ///Filter scale configuration
        fsc4: u1 = 0,
        ///FSC5 [5:5]
        ///Filter scale configuration
        fsc5: u1 = 0,
        ///FSC6 [6:6]
        ///Filter scale configuration
        fsc6: u1 = 0,
        ///FSC7 [7:7]
        ///Filter scale configuration
        fsc7: u1 = 0,
        ///FSC8 [8:8]
        ///Filter scale configuration
        fsc8: u1 = 0,
        ///FSC9 [9:9]
        ///Filter scale configuration
        fsc9: u1 = 0,
        ///FSC10 [10:10]
        ///Filter scale configuration
        fsc10: u1 = 0,
        ///FSC11 [11:11]
        ///Filter scale configuration
        fsc11: u1 = 0,
        ///FSC12 [12:12]
        ///Filter scale configuration
        fsc12: u1 = 0,
        ///FSC13 [13:13]
        ///Filter scale configuration
        fsc13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FS1R
    pub const can_fs1r = Register(can_fs1r_val).init(0x40006800 + 0x20C);

    //////////////////////////
    ///CAN_FFA1R
    const can_ffa1r_val = packed struct {
        ///FFA0 [0:0]
        ///Filter FIFO assignment for filter
        ///0
        ffa0: u1 = 0,
        ///FFA1 [1:1]
        ///Filter FIFO assignment for filter
        ///1
        ffa1: u1 = 0,
        ///FFA2 [2:2]
        ///Filter FIFO assignment for filter
        ///2
        ffa2: u1 = 0,
        ///FFA3 [3:3]
        ///Filter FIFO assignment for filter
        ///3
        ffa3: u1 = 0,
        ///FFA4 [4:4]
        ///Filter FIFO assignment for filter
        ///4
        ffa4: u1 = 0,
        ///FFA5 [5:5]
        ///Filter FIFO assignment for filter
        ///5
        ffa5: u1 = 0,
        ///FFA6 [6:6]
        ///Filter FIFO assignment for filter
        ///6
        ffa6: u1 = 0,
        ///FFA7 [7:7]
        ///Filter FIFO assignment for filter
        ///7
        ffa7: u1 = 0,
        ///FFA8 [8:8]
        ///Filter FIFO assignment for filter
        ///8
        ffa8: u1 = 0,
        ///FFA9 [9:9]
        ///Filter FIFO assignment for filter
        ///9
        ffa9: u1 = 0,
        ///FFA10 [10:10]
        ///Filter FIFO assignment for filter
        ///10
        ffa10: u1 = 0,
        ///FFA11 [11:11]
        ///Filter FIFO assignment for filter
        ///11
        ffa11: u1 = 0,
        ///FFA12 [12:12]
        ///Filter FIFO assignment for filter
        ///12
        ffa12: u1 = 0,
        ///FFA13 [13:13]
        ///Filter FIFO assignment for filter
        ///13
        ffa13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FFA1R
    pub const can_ffa1r = Register(can_ffa1r_val).init(0x40006800 + 0x214);

    //////////////////////////
    ///CAN_FA1R
    const can_fa1r_val = packed struct {
        ///FACT0 [0:0]
        ///Filter active
        fact0: u1 = 0,
        ///FACT1 [1:1]
        ///Filter active
        fact1: u1 = 0,
        ///FACT2 [2:2]
        ///Filter active
        fact2: u1 = 0,
        ///FACT3 [3:3]
        ///Filter active
        fact3: u1 = 0,
        ///FACT4 [4:4]
        ///Filter active
        fact4: u1 = 0,
        ///FACT5 [5:5]
        ///Filter active
        fact5: u1 = 0,
        ///FACT6 [6:6]
        ///Filter active
        fact6: u1 = 0,
        ///FACT7 [7:7]
        ///Filter active
        fact7: u1 = 0,
        ///FACT8 [8:8]
        ///Filter active
        fact8: u1 = 0,
        ///FACT9 [9:9]
        ///Filter active
        fact9: u1 = 0,
        ///FACT10 [10:10]
        ///Filter active
        fact10: u1 = 0,
        ///FACT11 [11:11]
        ///Filter active
        fact11: u1 = 0,
        ///FACT12 [12:12]
        ///Filter active
        fact12: u1 = 0,
        ///FACT13 [13:13]
        ///Filter active
        fact13: u1 = 0,
        _unused14: u18 = 0,
    };
    ///CAN_FA1R
    pub const can_fa1r = Register(can_fa1r_val).init(0x40006800 + 0x21C);

    //////////////////////////
    ///F0R1
    const f0r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 0 register 1
    pub const f0r1 = Register(f0r1_val).init(0x40006800 + 0x240);

    //////////////////////////
    ///F0R2
    const f0r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 0 register 2
    pub const f0r2 = Register(f0r2_val).init(0x40006800 + 0x244);

    //////////////////////////
    ///F1R1
    const f1r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 1 register 1
    pub const f1r1 = Register(f1r1_val).init(0x40006800 + 0x248);

    //////////////////////////
    ///F1R2
    const f1r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 1 register 2
    pub const f1r2 = Register(f1r2_val).init(0x40006800 + 0x24C);

    //////////////////////////
    ///F2R1
    const f2r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 2 register 1
    pub const f2r1 = Register(f2r1_val).init(0x40006800 + 0x250);

    //////////////////////////
    ///F2R2
    const f2r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 2 register 2
    pub const f2r2 = Register(f2r2_val).init(0x40006800 + 0x254);

    //////////////////////////
    ///F3R1
    const f3r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 3 register 1
    pub const f3r1 = Register(f3r1_val).init(0x40006800 + 0x258);

    //////////////////////////
    ///F3R2
    const f3r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 3 register 2
    pub const f3r2 = Register(f3r2_val).init(0x40006800 + 0x25C);

    //////////////////////////
    ///F4R1
    const f4r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 4 register 1
    pub const f4r1 = Register(f4r1_val).init(0x40006800 + 0x260);

    //////////////////////////
    ///F4R2
    const f4r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 4 register 2
    pub const f4r2 = Register(f4r2_val).init(0x40006800 + 0x264);

    //////////////////////////
    ///F5R1
    const f5r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 5 register 1
    pub const f5r1 = Register(f5r1_val).init(0x40006800 + 0x268);

    //////////////////////////
    ///F5R2
    const f5r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 5 register 2
    pub const f5r2 = Register(f5r2_val).init(0x40006800 + 0x26C);

    //////////////////////////
    ///F6R1
    const f6r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 6 register 1
    pub const f6r1 = Register(f6r1_val).init(0x40006800 + 0x270);

    //////////////////////////
    ///F6R2
    const f6r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 6 register 2
    pub const f6r2 = Register(f6r2_val).init(0x40006800 + 0x274);

    //////////////////////////
    ///F7R1
    const f7r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 7 register 1
    pub const f7r1 = Register(f7r1_val).init(0x40006800 + 0x278);

    //////////////////////////
    ///F7R2
    const f7r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 7 register 2
    pub const f7r2 = Register(f7r2_val).init(0x40006800 + 0x27C);

    //////////////////////////
    ///F8R1
    const f8r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 8 register 1
    pub const f8r1 = Register(f8r1_val).init(0x40006800 + 0x280);

    //////////////////////////
    ///F8R2
    const f8r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 8 register 2
    pub const f8r2 = Register(f8r2_val).init(0x40006800 + 0x284);

    //////////////////////////
    ///F9R1
    const f9r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 9 register 1
    pub const f9r1 = Register(f9r1_val).init(0x40006800 + 0x288);

    //////////////////////////
    ///F9R2
    const f9r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 9 register 2
    pub const f9r2 = Register(f9r2_val).init(0x40006800 + 0x28C);

    //////////////////////////
    ///F10R1
    const f10r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 10 register 1
    pub const f10r1 = Register(f10r1_val).init(0x40006800 + 0x290);

    //////////////////////////
    ///F10R2
    const f10r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 10 register 2
    pub const f10r2 = Register(f10r2_val).init(0x40006800 + 0x294);

    //////////////////////////
    ///F11R1
    const f11r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 11 register 1
    pub const f11r1 = Register(f11r1_val).init(0x40006800 + 0x298);

    //////////////////////////
    ///F11R2
    const f11r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 11 register 2
    pub const f11r2 = Register(f11r2_val).init(0x40006800 + 0x29C);

    //////////////////////////
    ///F12R1
    const f12r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 4 register 1
    pub const f12r1 = Register(f12r1_val).init(0x40006800 + 0x2A0);

    //////////////////////////
    ///F12R2
    const f12r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 12 register 2
    pub const f12r2 = Register(f12r2_val).init(0x40006800 + 0x2A4);

    //////////////////////////
    ///F13R1
    const f13r1_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 13 register 1
    pub const f13r1 = Register(f13r1_val).init(0x40006800 + 0x2A8);

    //////////////////////////
    ///F13R2
    const f13r2_val = packed struct {
        ///FB0 [0:0]
        ///Filter bits
        fb0: u1 = 0,
        ///FB1 [1:1]
        ///Filter bits
        fb1: u1 = 0,
        ///FB2 [2:2]
        ///Filter bits
        fb2: u1 = 0,
        ///FB3 [3:3]
        ///Filter bits
        fb3: u1 = 0,
        ///FB4 [4:4]
        ///Filter bits
        fb4: u1 = 0,
        ///FB5 [5:5]
        ///Filter bits
        fb5: u1 = 0,
        ///FB6 [6:6]
        ///Filter bits
        fb6: u1 = 0,
        ///FB7 [7:7]
        ///Filter bits
        fb7: u1 = 0,
        ///FB8 [8:8]
        ///Filter bits
        fb8: u1 = 0,
        ///FB9 [9:9]
        ///Filter bits
        fb9: u1 = 0,
        ///FB10 [10:10]
        ///Filter bits
        fb10: u1 = 0,
        ///FB11 [11:11]
        ///Filter bits
        fb11: u1 = 0,
        ///FB12 [12:12]
        ///Filter bits
        fb12: u1 = 0,
        ///FB13 [13:13]
        ///Filter bits
        fb13: u1 = 0,
        ///FB14 [14:14]
        ///Filter bits
        fb14: u1 = 0,
        ///FB15 [15:15]
        ///Filter bits
        fb15: u1 = 0,
        ///FB16 [16:16]
        ///Filter bits
        fb16: u1 = 0,
        ///FB17 [17:17]
        ///Filter bits
        fb17: u1 = 0,
        ///FB18 [18:18]
        ///Filter bits
        fb18: u1 = 0,
        ///FB19 [19:19]
        ///Filter bits
        fb19: u1 = 0,
        ///FB20 [20:20]
        ///Filter bits
        fb20: u1 = 0,
        ///FB21 [21:21]
        ///Filter bits
        fb21: u1 = 0,
        ///FB22 [22:22]
        ///Filter bits
        fb22: u1 = 0,
        ///FB23 [23:23]
        ///Filter bits
        fb23: u1 = 0,
        ///FB24 [24:24]
        ///Filter bits
        fb24: u1 = 0,
        ///FB25 [25:25]
        ///Filter bits
        fb25: u1 = 0,
        ///FB26 [26:26]
        ///Filter bits
        fb26: u1 = 0,
        ///FB27 [27:27]
        ///Filter bits
        fb27: u1 = 0,
        ///FB28 [28:28]
        ///Filter bits
        fb28: u1 = 0,
        ///FB29 [29:29]
        ///Filter bits
        fb29: u1 = 0,
        ///FB30 [30:30]
        ///Filter bits
        fb30: u1 = 0,
        ///FB31 [31:31]
        ///Filter bits
        fb31: u1 = 0,
    };
    ///Filter bank 13 register 2
    pub const f13r2 = Register(f13r2_val).init(0x40006800 + 0x2AC);
};

///Digital to analog converter
pub const dac = struct {

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///EN1 [0:0]
        ///DAC channel1 enable
        en1: u1 = 0,
        ///BOFF1 [1:1]
        ///DAC channel1 output buffer
        ///disable
        boff1: u1 = 0,
        ///TEN1 [2:2]
        ///DAC channel1 trigger
        ///enable
        ten1: u1 = 0,
        ///TSEL1 [3:5]
        ///DAC channel1 trigger
        ///selection
        tsel1: u3 = 0,
        ///WAVE1 [6:7]
        ///DAC channel1 noise/triangle wave
        ///generation enable
        wave1: u2 = 0,
        ///MAMP1 [8:11]
        ///DAC channel1 mask/amplitude
        ///selector
        mamp1: u4 = 0,
        ///DMAEN1 [12:12]
        ///DAC channel1 DMA enable
        dmaen1: u1 = 0,
        _unused13: u3 = 0,
        ///EN2 [16:16]
        ///DAC channel2 enable
        en2: u1 = 0,
        ///BOFF2 [17:17]
        ///DAC channel2 output buffer
        ///disable
        boff2: u1 = 0,
        ///TEN2 [18:18]
        ///DAC channel2 trigger
        ///enable
        ten2: u1 = 0,
        ///TSEL2 [19:21]
        ///DAC channel2 trigger
        ///selection
        tsel2: u3 = 0,
        ///WAVE2 [22:23]
        ///DAC channel2 noise/triangle wave
        ///generation enable
        wave2: u2 = 0,
        ///MAMP2 [24:27]
        ///DAC channel2 mask/amplitude
        ///selector
        mamp2: u4 = 0,
        ///DMAEN2 [28:28]
        ///DAC channel2 DMA enable
        dmaen2: u1 = 0,
        _unused29: u3 = 0,
    };
    ///Control register (DAC_CR)
    pub const cr = Register(cr_val).init(0x40007400 + 0x0);

    //////////////////////////
    ///SWTRIGR
    const swtrigr_val = packed struct {
        ///SWTRIG1 [0:0]
        ///DAC channel1 software
        ///trigger
        swtrig1: u1 = 0,
        ///SWTRIG2 [1:1]
        ///DAC channel2 software
        ///trigger
        swtrig2: u1 = 0,
        _unused2: u30 = 0,
    };
    ///DAC software trigger register
    ///(DAC_SWTRIGR)
    pub const swtrigr = RegisterRW(void, swtrigr_val).init(0x40007400 + 0x4);

    //////////////////////////
    ///DHR12R1
    const dhr12r1_val = packed struct {
        ///DACC1DHR [0:11]
        ///DAC channel1 12-bit right-aligned
        ///data
        dacc1dhr: u12 = 0,
        _unused12: u20 = 0,
    };
    ///DAC channel1 12-bit right-aligned data
    ///holding register(DAC_DHR12R1)
    pub const dhr12r1 = Register(dhr12r1_val).init(0x40007400 + 0x8);

    //////////////////////////
    ///DHR12L1
    const dhr12l1_val = packed struct {
        _unused0: u4 = 0,
        ///DACC1DHR [4:15]
        ///DAC channel1 12-bit left-aligned
        ///data
        dacc1dhr: u12 = 0,
        _unused16: u16 = 0,
    };
    ///DAC channel1 12-bit left aligned data
    ///holding register (DAC_DHR12L1)
    pub const dhr12l1 = Register(dhr12l1_val).init(0x40007400 + 0xC);

    //////////////////////////
    ///DHR8R1
    const dhr8r1_val = packed struct {
        ///DACC1DHR [0:7]
        ///DAC channel1 8-bit right-aligned
        ///data
        dacc1dhr: u8 = 0,
        _unused8: u24 = 0,
    };
    ///DAC channel1 8-bit right aligned data
    ///holding register (DAC_DHR8R1)
    pub const dhr8r1 = Register(dhr8r1_val).init(0x40007400 + 0x10);

    //////////////////////////
    ///DHR12R2
    const dhr12r2_val = packed struct {
        ///DACC2DHR [0:11]
        ///DAC channel2 12-bit right-aligned
        ///data
        dacc2dhr: u12 = 0,
        _unused12: u20 = 0,
    };
    ///DAC channel2 12-bit right aligned data
    ///holding register (DAC_DHR12R2)
    pub const dhr12r2 = Register(dhr12r2_val).init(0x40007400 + 0x14);

    //////////////////////////
    ///DHR12L2
    const dhr12l2_val = packed struct {
        _unused0: u4 = 0,
        ///DACC2DHR [4:15]
        ///DAC channel2 12-bit left-aligned
        ///data
        dacc2dhr: u12 = 0,
        _unused16: u16 = 0,
    };
    ///DAC channel2 12-bit left aligned data
    ///holding register (DAC_DHR12L2)
    pub const dhr12l2 = Register(dhr12l2_val).init(0x40007400 + 0x18);

    //////////////////////////
    ///DHR8R2
    const dhr8r2_val = packed struct {
        ///DACC2DHR [0:7]
        ///DAC channel2 8-bit right-aligned
        ///data
        dacc2dhr: u8 = 0,
        _unused8: u24 = 0,
    };
    ///DAC channel2 8-bit right-aligned data
    ///holding register (DAC_DHR8R2)
    pub const dhr8r2 = Register(dhr8r2_val).init(0x40007400 + 0x1C);

    //////////////////////////
    ///DHR12RD
    const dhr12rd_val = packed struct {
        ///DACC1DHR [0:11]
        ///DAC channel1 12-bit right-aligned
        ///data
        dacc1dhr: u12 = 0,
        _unused12: u4 = 0,
        ///DACC2DHR [16:27]
        ///DAC channel2 12-bit right-aligned
        ///data
        dacc2dhr: u12 = 0,
        _unused28: u4 = 0,
    };
    ///Dual DAC 12-bit right-aligned data holding
    ///register (DAC_DHR12RD), Bits 31:28 Reserved, Bits 15:12
    ///Reserved
    pub const dhr12rd = Register(dhr12rd_val).init(0x40007400 + 0x20);

    //////////////////////////
    ///DHR12LD
    const dhr12ld_val = packed struct {
        _unused0: u4 = 0,
        ///DACC1DHR [4:15]
        ///DAC channel1 12-bit left-aligned
        ///data
        dacc1dhr: u12 = 0,
        _unused16: u4 = 0,
        ///DACC2DHR [20:31]
        ///DAC channel2 12-bit right-aligned
        ///data
        dacc2dhr: u12 = 0,
    };
    ///DUAL DAC 12-bit left aligned data holding
    ///register (DAC_DHR12LD), Bits 19:16 Reserved, Bits 3:0
    ///Reserved
    pub const dhr12ld = Register(dhr12ld_val).init(0x40007400 + 0x24);

    //////////////////////////
    ///DHR8RD
    const dhr8rd_val = packed struct {
        ///DACC1DHR [0:7]
        ///DAC channel1 8-bit right-aligned
        ///data
        dacc1dhr: u8 = 0,
        ///DACC2DHR [8:15]
        ///DAC channel2 8-bit right-aligned
        ///data
        dacc2dhr: u8 = 0,
        _unused16: u16 = 0,
    };
    ///DUAL DAC 8-bit right aligned data holding
    ///register (DAC_DHR8RD), Bits 31:16 Reserved
    pub const dhr8rd = Register(dhr8rd_val).init(0x40007400 + 0x28);

    //////////////////////////
    ///DOR1
    const dor1_val = packed struct {
        ///DACC1DOR [0:11]
        ///DAC channel1 data output
        dacc1dor: u12 = 0,
        _unused12: u20 = 0,
    };
    ///DAC channel1 data output register
    ///(DAC_DOR1)
    pub const dor1 = RegisterRW(dor1_val, void).init(0x40007400 + 0x2C);

    //////////////////////////
    ///DOR2
    const dor2_val = packed struct {
        ///DACC2DOR [0:11]
        ///DAC channel2 data output
        dacc2dor: u12 = 0,
        _unused12: u20 = 0,
    };
    ///DAC channel2 data output register
    ///(DAC_DOR2)
    pub const dor2 = RegisterRW(dor2_val, void).init(0x40007400 + 0x30);
};

///Debug support
pub const dbg = struct {

    //////////////////////////
    ///IDCODE
    const idcode_val = packed struct {
        ///DEV_ID [0:11]
        ///DEV_ID
        dev_id: u12 = 0,
        _unused12: u4 = 0,
        ///REV_ID [16:31]
        ///REV_ID
        rev_id: u16 = 0,
    };
    ///DBGMCU_IDCODE
    pub const idcode = RegisterRW(idcode_val, void).init(0xE0042000 + 0x0);

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///DBG_SLEEP [0:0]
        ///DBG_SLEEP
        dbg_sleep: u1 = 0,
        ///DBG_STOP [1:1]
        ///DBG_STOP
        dbg_stop: u1 = 0,
        ///DBG_STANDBY [2:2]
        ///DBG_STANDBY
        dbg_standby: u1 = 0,
        _unused3: u2 = 0,
        ///TRACE_IOEN [5:5]
        ///TRACE_IOEN
        trace_ioen: u1 = 0,
        ///TRACE_MODE [6:7]
        ///TRACE_MODE
        trace_mode: u2 = 0,
        ///DBG_IWDG_STOP [8:8]
        ///DBG_IWDG_STOP
        dbg_iwdg_stop: u1 = 0,
        ///DBG_WWDG_STOP [9:9]
        ///DBG_WWDG_STOP
        dbg_wwdg_stop: u1 = 0,
        ///DBG_TIM1_STOP [10:10]
        ///DBG_TIM1_STOP
        dbg_tim1_stop: u1 = 0,
        ///DBG_TIM2_STOP [11:11]
        ///DBG_TIM2_STOP
        dbg_tim2_stop: u1 = 0,
        ///DBG_TIM3_STOP [12:12]
        ///DBG_TIM3_STOP
        dbg_tim3_stop: u1 = 0,
        ///DBG_TIM4_STOP [13:13]
        ///DBG_TIM4_STOP
        dbg_tim4_stop: u1 = 0,
        ///DBG_CAN1_STOP [14:14]
        ///DBG_CAN1_STOP
        dbg_can1_stop: u1 = 0,
        ///DBG_I2C1_SMBUS_TIMEOUT [15:15]
        ///DBG_I2C1_SMBUS_TIMEOUT
        dbg_i2c1_smbus_timeout: u1 = 0,
        ///DBG_I2C2_SMBUS_TIMEOUT [16:16]
        ///DBG_I2C2_SMBUS_TIMEOUT
        dbg_i2c2_smbus_timeout: u1 = 0,
        ///DBG_TIM8_STOP [17:17]
        ///DBG_TIM8_STOP
        dbg_tim8_stop: u1 = 0,
        ///DBG_TIM5_STOP [18:18]
        ///DBG_TIM5_STOP
        dbg_tim5_stop: u1 = 0,
        ///DBG_TIM6_STOP [19:19]
        ///DBG_TIM6_STOP
        dbg_tim6_stop: u1 = 0,
        ///DBG_TIM7_STOP [20:20]
        ///DBG_TIM7_STOP
        dbg_tim7_stop: u1 = 0,
        ///DBG_CAN2_STOP [21:21]
        ///DBG_CAN2_STOP
        dbg_can2_stop: u1 = 0,
        _unused22: u10 = 0,
    };
    ///DBGMCU_CR
    pub const cr = Register(cr_val).init(0xE0042000 + 0x4);
};

///Universal asynchronous receiver
///transmitter
pub const uart4 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///PE [0:0]
        ///Parity error
        pe: u1 = 0,
        ///FE [1:1]
        ///Framing error
        fe: u1 = 0,
        ///NE [2:2]
        ///Noise error flag
        ne: u1 = 0,
        ///ORE [3:3]
        ///Overrun error
        ore: u1 = 0,
        ///IDLE [4:4]
        ///IDLE line detected
        idle: u1 = 0,
        ///RXNE [5:5]
        ///Read data register not
        ///empty
        rxne: u1 = 0,
        ///TC [6:6]
        ///Transmission complete
        tc: u1 = 0,
        ///TXE [7:7]
        ///Transmit data register
        ///empty
        txe: u1 = 0,
        ///LBD [8:8]
        ///LIN break detection flag
        lbd: u1 = 0,
        _unused9: u23 = 0,
    };
    ///UART4_SR
    pub const sr = Register(sr_val).init(0x40004C00 + 0x0);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:8]
        ///DR
        dr: u9 = 0,
        _unused9: u23 = 0,
    };
    ///UART4_DR
    pub const dr = Register(dr_val).init(0x40004C00 + 0x4);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///DIV_Fraction [0:3]
        ///DIV_Fraction
        div_fraction: u4 = 0,
        ///DIV_Mantissa [4:15]
        ///DIV_Mantissa
        div_mantissa: u12 = 0,
        _unused16: u16 = 0,
    };
    ///UART4_BRR
    pub const brr = Register(brr_val).init(0x40004C00 + 0x8);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///SBK [0:0]
        ///Send break
        sbk: u1 = 0,
        ///RWU [1:1]
        ///Receiver wakeup
        rwu: u1 = 0,
        ///RE [2:2]
        ///Receiver enable
        re: u1 = 0,
        ///TE [3:3]
        ///Transmitter enable
        te: u1 = 0,
        ///IDLEIE [4:4]
        ///IDLE interrupt enable
        idleie: u1 = 0,
        ///RXNEIE [5:5]
        ///RXNE interrupt enable
        rxneie: u1 = 0,
        ///TCIE [6:6]
        ///Transmission complete interrupt
        ///enable
        tcie: u1 = 0,
        ///TXEIE [7:7]
        ///TXE interrupt enable
        txeie: u1 = 0,
        ///PEIE [8:8]
        ///PE interrupt enable
        peie: u1 = 0,
        ///PS [9:9]
        ///Parity selection
        ps: u1 = 0,
        ///PCE [10:10]
        ///Parity control enable
        pce: u1 = 0,
        ///WAKE [11:11]
        ///Wakeup method
        wake: u1 = 0,
        ///M [12:12]
        ///Word length
        m: u1 = 0,
        ///UE [13:13]
        ///USART enable
        ue: u1 = 0,
        _unused14: u18 = 0,
    };
    ///UART4_CR1
    pub const cr1 = Register(cr1_val).init(0x40004C00 + 0xC);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADD [0:3]
        ///Address of the USART node
        add: u4 = 0,
        _unused4: u1 = 0,
        ///LBDL [5:5]
        ///lin break detection length
        lbdl: u1 = 0,
        ///LBDIE [6:6]
        ///LIN break detection interrupt
        ///enable
        lbdie: u1 = 0,
        _unused7: u5 = 0,
        ///STOP [12:13]
        ///STOP bits
        stop: u2 = 0,
        ///LINEN [14:14]
        ///LIN mode enable
        linen: u1 = 0,
        _unused15: u17 = 0,
    };
    ///UART4_CR2
    pub const cr2 = Register(cr2_val).init(0x40004C00 + 0x10);

    //////////////////////////
    ///CR3
    const cr3_val = packed struct {
        ///EIE [0:0]
        ///Error interrupt enable
        eie: u1 = 0,
        ///IREN [1:1]
        ///IrDA mode enable
        iren: u1 = 0,
        ///IRLP [2:2]
        ///IrDA low-power
        irlp: u1 = 0,
        ///HDSEL [3:3]
        ///Half-duplex selection
        hdsel: u1 = 0,
        _unused4: u2 = 0,
        ///DMAR [6:6]
        ///DMA enable receiver
        dmar: u1 = 0,
        ///DMAT [7:7]
        ///DMA enable transmitter
        dmat: u1 = 0,
        _unused8: u24 = 0,
    };
    ///UART4_CR3
    pub const cr3 = Register(cr3_val).init(0x40004C00 + 0x14);
};

///Universal asynchronous receiver
///transmitter
pub const uart5 = struct {

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///PE [0:0]
        ///PE
        pe: u1 = 0,
        ///FE [1:1]
        ///FE
        fe: u1 = 0,
        ///NE [2:2]
        ///NE
        ne: u1 = 0,
        ///ORE [3:3]
        ///ORE
        ore: u1 = 0,
        ///IDLE [4:4]
        ///IDLE
        idle: u1 = 0,
        ///RXNE [5:5]
        ///RXNE
        rxne: u1 = 0,
        ///TC [6:6]
        ///TC
        tc: u1 = 0,
        ///TXE [7:7]
        ///TXE
        txe: u1 = 0,
        ///LBD [8:8]
        ///LBD
        lbd: u1 = 0,
        _unused9: u23 = 0,
    };
    ///UART4_SR
    pub const sr = Register(sr_val).init(0x40005000 + 0x0);

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:8]
        ///DR
        dr: u9 = 0,
        _unused9: u23 = 0,
    };
    ///UART4_DR
    pub const dr = Register(dr_val).init(0x40005000 + 0x4);

    //////////////////////////
    ///BRR
    const brr_val = packed struct {
        ///DIV_Fraction [0:3]
        ///DIV_Fraction
        div_fraction: u4 = 0,
        ///DIV_Mantissa [4:15]
        ///DIV_Mantissa
        div_mantissa: u12 = 0,
        _unused16: u16 = 0,
    };
    ///UART4_BRR
    pub const brr = Register(brr_val).init(0x40005000 + 0x8);

    //////////////////////////
    ///CR1
    const cr1_val = packed struct {
        ///SBK [0:0]
        ///SBK
        sbk: u1 = 0,
        ///RWU [1:1]
        ///RWU
        rwu: u1 = 0,
        ///RE [2:2]
        ///RE
        re: u1 = 0,
        ///TE [3:3]
        ///TE
        te: u1 = 0,
        ///IDLEIE [4:4]
        ///IDLEIE
        idleie: u1 = 0,
        ///RXNEIE [5:5]
        ///RXNEIE
        rxneie: u1 = 0,
        ///TCIE [6:6]
        ///TCIE
        tcie: u1 = 0,
        ///TXEIE [7:7]
        ///TXEIE
        txeie: u1 = 0,
        ///PEIE [8:8]
        ///PEIE
        peie: u1 = 0,
        ///PS [9:9]
        ///PS
        ps: u1 = 0,
        ///PCE [10:10]
        ///PCE
        pce: u1 = 0,
        ///WAKE [11:11]
        ///WAKE
        wake: u1 = 0,
        ///M [12:12]
        ///M
        m: u1 = 0,
        ///UE [13:13]
        ///UE
        ue: u1 = 0,
        _unused14: u18 = 0,
    };
    ///UART4_CR1
    pub const cr1 = Register(cr1_val).init(0x40005000 + 0xC);

    //////////////////////////
    ///CR2
    const cr2_val = packed struct {
        ///ADD [0:3]
        ///ADD
        add: u4 = 0,
        _unused4: u1 = 0,
        ///LBDL [5:5]
        ///LBDL
        lbdl: u1 = 0,
        ///LBDIE [6:6]
        ///LBDIE
        lbdie: u1 = 0,
        _unused7: u5 = 0,
        ///STOP [12:13]
        ///STOP
        stop: u2 = 0,
        ///LINEN [14:14]
        ///LINEN
        linen: u1 = 0,
        _unused15: u17 = 0,
    };
    ///UART4_CR2
    pub const cr2 = Register(cr2_val).init(0x40005000 + 0x10);

    //////////////////////////
    ///CR3
    const cr3_val = packed struct {
        ///EIE [0:0]
        ///Error interrupt enable
        eie: u1 = 0,
        ///IREN [1:1]
        ///IrDA mode enable
        iren: u1 = 0,
        ///IRLP [2:2]
        ///IrDA low-power
        irlp: u1 = 0,
        ///HDSEL [3:3]
        ///Half-duplex selection
        hdsel: u1 = 0,
        _unused4: u3 = 0,
        ///DMAT [7:7]
        ///DMA enable transmitter
        dmat: u1 = 0,
        _unused8: u24 = 0,
    };
    ///UART4_CR3
    pub const cr3 = Register(cr3_val).init(0x40005000 + 0x14);
};

///CRC calculation unit
pub const crc = struct {

    //////////////////////////
    ///DR
    const dr_val = packed struct {
        ///DR [0:31]
        ///Data Register
        dr: u32 = 4294967295,
    };
    ///Data register
    pub const dr = Register(dr_val).init(0x40023000 + 0x0);

    //////////////////////////
    ///IDR
    const idr_val = packed struct {
        ///IDR [0:7]
        ///Independent Data register
        idr: u8 = 0,
        _unused8: u24 = 0,
    };
    ///Independent Data register
    pub const idr = Register(idr_val).init(0x40023000 + 0x4);

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///RESET [0:0]
        ///Reset bit
        reset: u1 = 0,
        _unused1: u31 = 0,
    };
    ///Control register
    pub const cr = RegisterRW(void, cr_val).init(0x40023000 + 0x8);
};

///FLASH
pub const flash = struct {

    //////////////////////////
    ///ACR
    const acr_val = packed struct {
        ///LATENCY [0:2]
        ///Latency
        latency: u3 = 0,
        ///HLFCYA [3:3]
        ///Flash half cycle access
        ///enable
        hlfcya: u1 = 0,
        ///PRFTBE [4:4]
        ///Prefetch buffer enable
        prftbe: u1 = 1,
        ///PRFTBS [5:5]
        ///Prefetch buffer status
        prftbs: u1 = 1,
        _unused6: u26 = 0,
    };
    ///Flash access control register
    pub const acr = Register(acr_val).init(0x40022000 + 0x0);

    //////////////////////////
    ///KEYR
    const keyr_val = packed struct {
        ///KEY [0:31]
        ///FPEC key
        key: u32 = 0,
    };
    ///Flash key register
    pub const keyr = RegisterRW(void, keyr_val).init(0x40022000 + 0x4);

    //////////////////////////
    ///OPTKEYR
    const optkeyr_val = packed struct {
        ///OPTKEY [0:31]
        ///Option byte key
        optkey: u32 = 0,
    };
    ///Flash option key register
    pub const optkeyr = RegisterRW(void, optkeyr_val).init(0x40022000 + 0x8);

    //////////////////////////
    ///SR
    const sr_val = packed struct {
        ///BSY [0:0]
        ///Busy
        bsy: u1 = 0,
        _unused1: u1 = 0,
        ///PGERR [2:2]
        ///Programming error
        pgerr: u1 = 0,
        _unused3: u1 = 0,
        ///WRPRTERR [4:4]
        ///Write protection error
        wrprterr: u1 = 0,
        ///EOP [5:5]
        ///End of operation
        eop: u1 = 0,
        _unused6: u26 = 0,
    };
    ///Status register
    pub const sr = Register(sr_val).init(0x40022000 + 0xC);

    //////////////////////////
    ///CR
    const cr_val = packed struct {
        ///PG [0:0]
        ///Programming
        pg: u1 = 0,
        ///PER [1:1]
        ///Page Erase
        per: u1 = 0,
        ///MER [2:2]
        ///Mass Erase
        mer: u1 = 0,
        _unused3: u1 = 0,
        ///OPTPG [4:4]
        ///Option byte programming
        optpg: u1 = 0,
        ///OPTER [5:5]
        ///Option byte erase
        opter: u1 = 0,
        ///STRT [6:6]
        ///Start
        strt: u1 = 0,
        ///LOCK [7:7]
        ///Lock
        lock: u1 = 1,
        _unused8: u1 = 0,
        ///OPTWRE [9:9]
        ///Option bytes write enable
        optwre: u1 = 0,
        ///ERRIE [10:10]
        ///Error interrupt enable
        errie: u1 = 0,
        _unused11: u1 = 0,
        ///EOPIE [12:12]
        ///End of operation interrupt
        ///enable
        eopie: u1 = 0,
        _unused13: u19 = 0,
    };
    ///Control register
    pub const cr = Register(cr_val).init(0x40022000 + 0x10);

    //////////////////////////
    ///AR
    const ar_val = packed struct {
        ///FAR [0:31]
        ///Flash Address
        far: u32 = 0,
    };
    ///Flash address register
    pub const ar = RegisterRW(void, ar_val).init(0x40022000 + 0x14);

    //////////////////////////
    ///OBR
    const obr_val = packed struct {
        ///OPTERR [0:0]
        ///Option byte error
        opterr: u1 = 0,
        ///RDPRT [1:1]
        ///Read protection
        rdprt: u1 = 0,
        ///WDG_SW [2:2]
        ///WDG_SW
        wdg_sw: u1 = 1,
        ///nRST_STOP [3:3]
        ///nRST_STOP
        n_rst_stop: u1 = 1,
        ///nRST_STDBY [4:4]
        ///nRST_STDBY
        n_rst_stdby: u1 = 1,
        _unused5: u5 = 0,
        ///Data0 [10:17]
        ///Data0
        data0: u8 = 255,
        ///Data1 [18:25]
        ///Data1
        data1: u8 = 255,
        _unused26: u6 = 0,
    };
    ///Option byte register
    pub const obr = RegisterRW(obr_val, void).init(0x40022000 + 0x1C);

    //////////////////////////
    ///WRPR
    const wrpr_val = packed struct {
        ///WRP [0:31]
        ///Write protect
        wrp: u32 = 4294967295,
    };
    ///Write protection register
    pub const wrpr = RegisterRW(wrpr_val, void).init(0x40022000 + 0x20);
};

///Nested Vectored Interrupt
///Controller
pub const nvic = struct {

    //////////////////////////
    ///ICTR
    const ictr_val = packed struct {
        ///INTLINESNUM [0:3]
        ///Total number of interrupt lines in
        ///groups
        intlinesnum: u4 = 0,
        _unused4: u28 = 0,
    };
    ///Interrupt Controller Type
    ///Register
    pub const ictr = RegisterRW(ictr_val, void).init(0xE000E000 + 0x4);

    //////////////////////////
    ///STIR
    const stir_val = packed struct {
        ///INTID [0:8]
        ///interrupt to be triggered
        intid: u9 = 0,
        _unused9: u23 = 0,
    };
    ///Software Triggered Interrupt
    ///Register
    pub const stir = RegisterRW(void, stir_val).init(0xE000E000 + 0xF00);

    //////////////////////////
    ///ISER0
    const iser0_val = packed struct {
        ///SETENA [0:31]
        ///SETENA
        setena: u32 = 0,
    };
    ///Interrupt Set-Enable Register
    pub const iser0 = Register(iser0_val).init(0xE000E000 + 0x100);

    //////////////////////////
    ///ISER1
    const iser1_val = packed struct {
        ///SETENA [0:31]
        ///SETENA
        setena: u32 = 0,
    };
    ///Interrupt Set-Enable Register
    pub const iser1 = Register(iser1_val).init(0xE000E000 + 0x104);

    //////////////////////////
    ///ICER0
    const icer0_val = packed struct {
        ///CLRENA [0:31]
        ///CLRENA
        clrena: u32 = 0,
    };
    ///Interrupt Clear-Enable
    ///Register
    pub const icer0 = Register(icer0_val).init(0xE000E000 + 0x180);

    //////////////////////////
    ///ICER1
    const icer1_val = packed struct {
        ///CLRENA [0:31]
        ///CLRENA
        clrena: u32 = 0,
    };
    ///Interrupt Clear-Enable
    ///Register
    pub const icer1 = Register(icer1_val).init(0xE000E000 + 0x184);

    //////////////////////////
    ///ISPR0
    const ispr0_val = packed struct {
        ///SETPEND [0:31]
        ///SETPEND
        setpend: u32 = 0,
    };
    ///Interrupt Set-Pending Register
    pub const ispr0 = Register(ispr0_val).init(0xE000E000 + 0x200);

    //////////////////////////
    ///ISPR1
    const ispr1_val = packed struct {
        ///SETPEND [0:31]
        ///SETPEND
        setpend: u32 = 0,
    };
    ///Interrupt Set-Pending Register
    pub const ispr1 = Register(ispr1_val).init(0xE000E000 + 0x204);

    //////////////////////////
    ///ICPR0
    const icpr0_val = packed struct {
        ///CLRPEND [0:31]
        ///CLRPEND
        clrpend: u32 = 0,
    };
    ///Interrupt Clear-Pending
    ///Register
    pub const icpr0 = Register(icpr0_val).init(0xE000E000 + 0x280);

    //////////////////////////
    ///ICPR1
    const icpr1_val = packed struct {
        ///CLRPEND [0:31]
        ///CLRPEND
        clrpend: u32 = 0,
    };
    ///Interrupt Clear-Pending
    ///Register
    pub const icpr1 = Register(icpr1_val).init(0xE000E000 + 0x284);

    //////////////////////////
    ///IABR0
    const iabr0_val = packed struct {
        ///ACTIVE [0:31]
        ///ACTIVE
        active: u32 = 0,
    };
    ///Interrupt Active Bit Register
    pub const iabr0 = RegisterRW(iabr0_val, void).init(0xE000E000 + 0x300);

    //////////////////////////
    ///IABR1
    const iabr1_val = packed struct {
        ///ACTIVE [0:31]
        ///ACTIVE
        active: u32 = 0,
    };
    ///Interrupt Active Bit Register
    pub const iabr1 = RegisterRW(iabr1_val, void).init(0xE000E000 + 0x304);

    //////////////////////////
    ///IPR0
    const ipr0_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr0 = Register(ipr0_val).init(0xE000E000 + 0x400);

    //////////////////////////
    ///IPR1
    const ipr1_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr1 = Register(ipr1_val).init(0xE000E000 + 0x404);

    //////////////////////////
    ///IPR2
    const ipr2_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr2 = Register(ipr2_val).init(0xE000E000 + 0x408);

    //////////////////////////
    ///IPR3
    const ipr3_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr3 = Register(ipr3_val).init(0xE000E000 + 0x40C);

    //////////////////////////
    ///IPR4
    const ipr4_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr4 = Register(ipr4_val).init(0xE000E000 + 0x410);

    //////////////////////////
    ///IPR5
    const ipr5_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr5 = Register(ipr5_val).init(0xE000E000 + 0x414);

    //////////////////////////
    ///IPR6
    const ipr6_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr6 = Register(ipr6_val).init(0xE000E000 + 0x418);

    //////////////////////////
    ///IPR7
    const ipr7_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr7 = Register(ipr7_val).init(0xE000E000 + 0x41C);

    //////////////////////////
    ///IPR8
    const ipr8_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr8 = Register(ipr8_val).init(0xE000E000 + 0x420);

    //////////////////////////
    ///IPR9
    const ipr9_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr9 = Register(ipr9_val).init(0xE000E000 + 0x424);

    //////////////////////////
    ///IPR10
    const ipr10_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr10 = Register(ipr10_val).init(0xE000E000 + 0x428);

    //////////////////////////
    ///IPR11
    const ipr11_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr11 = Register(ipr11_val).init(0xE000E000 + 0x42C);

    //////////////////////////
    ///IPR12
    const ipr12_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr12 = Register(ipr12_val).init(0xE000E000 + 0x430);

    //////////////////////////
    ///IPR13
    const ipr13_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr13 = Register(ipr13_val).init(0xE000E000 + 0x434);

    //////////////////////////
    ///IPR14
    const ipr14_val = packed struct {
        ///IPR_N0 [0:7]
        ///IPR_N0
        ipr_n0: u8 = 0,
        ///IPR_N1 [8:15]
        ///IPR_N1
        ipr_n1: u8 = 0,
        ///IPR_N2 [16:23]
        ///IPR_N2
        ipr_n2: u8 = 0,
        ///IPR_N3 [24:31]
        ///IPR_N3
        ipr_n3: u8 = 0,
    };
    ///Interrupt Priority Register
    pub const ipr14 = Register(ipr14_val).init(0xE000E000 + 0x438);
};

///Universal serial bus full-speed device
///interface
pub const usb = struct {

    //////////////////////////
    ///EP0R
    const ep0r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 0 register
    pub const ep0r = Register(ep0r_val).init(0x40005C00 + 0x0);

    //////////////////////////
    ///EP1R
    const ep1r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 1 register
    pub const ep1r = Register(ep1r_val).init(0x40005C00 + 0x4);

    //////////////////////////
    ///EP2R
    const ep2r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 2 register
    pub const ep2r = Register(ep2r_val).init(0x40005C00 + 0x8);

    //////////////////////////
    ///EP3R
    const ep3r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 3 register
    pub const ep3r = Register(ep3r_val).init(0x40005C00 + 0xC);

    //////////////////////////
    ///EP4R
    const ep4r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 4 register
    pub const ep4r = Register(ep4r_val).init(0x40005C00 + 0x10);

    //////////////////////////
    ///EP5R
    const ep5r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 5 register
    pub const ep5r = Register(ep5r_val).init(0x40005C00 + 0x14);

    //////////////////////////
    ///EP6R
    const ep6r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 6 register
    pub const ep6r = Register(ep6r_val).init(0x40005C00 + 0x18);

    //////////////////////////
    ///EP7R
    const ep7r_val = packed struct {
        ///EA [0:3]
        ///Endpoint address
        ea: u4 = 0,
        ///STAT_TX [4:5]
        ///Status bits, for transmission
        ///transfers
        stat_tx: u2 = 0,
        ///DTOG_TX [6:6]
        ///Data Toggle, for transmission
        ///transfers
        dtog_tx: u1 = 0,
        ///CTR_TX [7:7]
        ///Correct Transfer for
        ///transmission
        ctr_tx: u1 = 0,
        ///EP_KIND [8:8]
        ///Endpoint kind
        ep_kind: u1 = 0,
        ///EP_TYPE [9:10]
        ///Endpoint type
        ep_type: u2 = 0,
        ///SETUP [11:11]
        ///Setup transaction
        ///completed
        setup: u1 = 0,
        ///STAT_RX [12:13]
        ///Status bits, for reception
        ///transfers
        stat_rx: u2 = 0,
        ///DTOG_RX [14:14]
        ///Data Toggle, for reception
        ///transfers
        dtog_rx: u1 = 0,
        ///CTR_RX [15:15]
        ///Correct transfer for
        ///reception
        ctr_rx: u1 = 0,
        _unused16: u16 = 0,
    };
    ///endpoint 7 register
    pub const ep7r = Register(ep7r_val).init(0x40005C00 + 0x1C);

    //////////////////////////
    ///CNTR
    const cntr_val = packed struct {
        ///FRES [0:0]
        ///Force USB Reset
        fres: u1 = 1,
        ///PDWN [1:1]
        ///Power down
        pdwn: u1 = 1,
        ///LPMODE [2:2]
        ///Low-power mode
        lpmode: u1 = 0,
        ///FSUSP [3:3]
        ///Force suspend
        fsusp: u1 = 0,
        ///RESUME [4:4]
        ///Resume request
        _resume: u1 = 0,
        _unused5: u3 = 0,
        ///ESOFM [8:8]
        ///Expected start of frame interrupt
        ///mask
        esofm: u1 = 0,
        ///SOFM [9:9]
        ///Start of frame interrupt
        ///mask
        sofm: u1 = 0,
        ///RESETM [10:10]
        ///USB reset interrupt mask
        resetm: u1 = 0,
        ///SUSPM [11:11]
        ///Suspend mode interrupt
        ///mask
        suspm: u1 = 0,
        ///WKUPM [12:12]
        ///Wakeup interrupt mask
        wkupm: u1 = 0,
        ///ERRM [13:13]
        ///Error interrupt mask
        errm: u1 = 0,
        ///PMAOVRM [14:14]
        ///Packet memory area over / underrun
        ///interrupt mask
        pmaovrm: u1 = 0,
        ///CTRM [15:15]
        ///Correct transfer interrupt
        ///mask
        ctrm: u1 = 0,
        _unused16: u16 = 0,
    };
    ///control register
    pub const cntr = Register(cntr_val).init(0x40005C00 + 0x40);

    //////////////////////////
    ///ISTR
    const istr_val = packed struct {
        ///EP_ID [0:3]
        ///Endpoint Identifier
        ep_id: u4 = 0,
        ///DIR [4:4]
        ///Direction of transaction
        dir: u1 = 0,
        _unused5: u3 = 0,
        ///ESOF [8:8]
        ///Expected start frame
        esof: u1 = 0,
        ///SOF [9:9]
        ///start of frame
        sof: u1 = 0,
        ///RESET [10:10]
        ///reset request
        reset: u1 = 0,
        ///SUSP [11:11]
        ///Suspend mode request
        susp: u1 = 0,
        ///WKUP [12:12]
        ///Wakeup
        wkup: u1 = 0,
        ///ERR [13:13]
        ///Error
        err: u1 = 0,
        ///PMAOVR [14:14]
        ///Packet memory area over /
        ///underrun
        pmaovr: u1 = 0,
        ///CTR [15:15]
        ///Correct transfer
        ctr: u1 = 0,
        _unused16: u16 = 0,
    };
    ///interrupt status register
    pub const istr = Register(istr_val).init(0x40005C00 + 0x44);

    //////////////////////////
    ///FNR
    const _fnr_val = packed struct {
        ///FN [0:10]
        ///Frame number
        _fn: u11 = 0,
        ///LSOF [11:12]
        ///Lost SOF
        lsof: u2 = 0,
        ///LCK [13:13]
        ///Locked
        lck: u1 = 0,
        ///RXDM [14:14]
        ///Receive data - line status
        rxdm: u1 = 0,
        ///RXDP [15:15]
        ///Receive data + line status
        rxdp: u1 = 0,
        _unused16: u16 = 0,
    };
    ///frame number register
    pub const _fnr = RegisterRW(_fnr_val, void).init(0x40005C00 + 0x48);

    //////////////////////////
    ///DADDR
    const daddr_val = packed struct {
        ///ADD [0:6]
        ///Device address
        add: u7 = 0,
        ///EF [7:7]
        ///Enable function
        ef: u1 = 0,
        _unused8: u24 = 0,
    };
    ///device address
    pub const daddr = Register(daddr_val).init(0x40005C00 + 0x4C);

    //////////////////////////
    ///BTABLE
    const btable_val = packed struct {
        _unused0: u3 = 0,
        ///BTABLE [3:15]
        ///Buffer table
        btable: u13 = 0,
        _unused16: u16 = 0,
    };
    ///Buffer table address
    pub const btable = Register(btable_val).init(0x40005C00 + 0x50);
};

///USB on the go full speed
pub const otg_fs_device = struct {

    //////////////////////////
    ///FS_DCFG
    const fs_dcfg_val = packed struct {
        ///DSPD [0:1]
        ///Device speed
        dspd: u2 = 0,
        ///NZLSOHSK [2:2]
        ///Non-zero-length status OUT
        ///handshake
        nzlsohsk: u1 = 0,
        _unused3: u1 = 0,
        ///DAD [4:10]
        ///Device address
        dad: u7 = 0,
        ///PFIVL [11:12]
        ///Periodic frame interval
        pfivl: u2 = 0,
        _unused13: u19 = 0,
    };
    ///OTG_FS device configuration register
    ///(OTG_FS_DCFG)
    pub const fs_dcfg = Register(fs_dcfg_val).init(0x50000800 + 0x0);

    //////////////////////////
    ///FS_DCTL
    const fs_dctl_val = packed struct {
        ///RWUSIG [0:0]
        ///Remote wakeup signaling
        rwusig: u1 = 0,
        ///SDIS [1:1]
        ///Soft disconnect
        sdis: u1 = 0,
        ///GINSTS [2:2]
        ///Global IN NAK status
        ginsts: u1 = 0,
        ///GONSTS [3:3]
        ///Global OUT NAK status
        gonsts: u1 = 0,
        ///TCTL [4:6]
        ///Test control
        tctl: u3 = 0,
        ///SGINAK [7:7]
        ///Set global IN NAK
        sginak: u1 = 0,
        ///CGINAK [8:8]
        ///Clear global IN NAK
        cginak: u1 = 0,
        ///SGONAK [9:9]
        ///Set global OUT NAK
        sgonak: u1 = 0,
        ///CGONAK [10:10]
        ///Clear global OUT NAK
        cgonak: u1 = 0,
        ///POPRGDNE [11:11]
        ///Power-on programming done
        poprgdne: u1 = 0,
        _unused12: u20 = 0,
    };
    ///OTG_FS device control register
    ///(OTG_FS_DCTL)
    pub const fs_dctl = Register(fs_dctl_val).init(0x50000800 + 0x4);

    //////////////////////////
    ///FS_DSTS
    const fs_dsts_val = packed struct {
        ///SUSPSTS [0:0]
        ///Suspend status
        suspsts: u1 = 0,
        ///ENUMSPD [1:2]
        ///Enumerated speed
        enumspd: u2 = 0,
        ///EERR [3:3]
        ///Erratic error
        eerr: u1 = 0,
        _unused4: u4 = 0,
        ///FNSOF [8:21]
        ///Frame number of the received
        ///SOF
        _fnsof: u14 = 0,
        _unused22: u10 = 0,
    };
    ///OTG_FS device status register
    ///(OTG_FS_DSTS)
    pub const fs_dsts = RegisterRW(fs_dsts_val, void).init(0x50000800 + 0x8);

    //////////////////////////
    ///FS_DIEPMSK
    const fs_diepmsk_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed interrupt
        ///mask
        xfrcm: u1 = 0,
        ///EPDM [1:1]
        ///Endpoint disabled interrupt
        ///mask
        epdm: u1 = 0,
        _unused2: u1 = 0,
        ///TOM [3:3]
        ///Timeout condition mask (Non-isochronous
        ///endpoints)
        tom: u1 = 0,
        ///ITTXFEMSK [4:4]
        ///IN token received when TxFIFO empty
        ///mask
        ittxfemsk: u1 = 0,
        ///INEPNMM [5:5]
        ///IN token received with EP mismatch
        ///mask
        inepnmm: u1 = 0,
        ///INEPNEM [6:6]
        ///IN endpoint NAK effective
        ///mask
        inepnem: u1 = 0,
        _unused7: u25 = 0,
    };
    ///OTG_FS device IN endpoint common interrupt
    ///mask register (OTG_FS_DIEPMSK)
    pub const fs_diepmsk = Register(fs_diepmsk_val).init(0x50000800 + 0x10);

    //////////////////////////
    ///FS_DOEPMSK
    const fs_doepmsk_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed interrupt
        ///mask
        xfrcm: u1 = 0,
        ///EPDM [1:1]
        ///Endpoint disabled interrupt
        ///mask
        epdm: u1 = 0,
        _unused2: u1 = 0,
        ///STUPM [3:3]
        ///SETUP phase done mask
        stupm: u1 = 0,
        ///OTEPDM [4:4]
        ///OUT token received when endpoint
        ///disabled mask
        otepdm: u1 = 0,
        _unused5: u27 = 0,
    };
    ///OTG_FS device OUT endpoint common interrupt
    ///mask register (OTG_FS_DOEPMSK)
    pub const fs_doepmsk = Register(fs_doepmsk_val).init(0x50000800 + 0x14);

    //////////////////////////
    ///FS_DAINT
    const fs_daint_val = packed struct {
        ///IEPINT [0:15]
        ///IN endpoint interrupt bits
        iepint: u16 = 0,
        ///OEPINT [16:31]
        ///OUT endpoint interrupt
        ///bits
        oepint: u16 = 0,
    };
    ///OTG_FS device all endpoints interrupt
    ///register (OTG_FS_DAINT)
    pub const fs_daint = RegisterRW(fs_daint_val, void).init(0x50000800 + 0x18);

    //////////////////////////
    ///FS_DAINTMSK
    const fs_daintmsk_val = packed struct {
        ///IEPM [0:15]
        ///IN EP interrupt mask bits
        iepm: u16 = 0,
        ///OEPINT [16:31]
        ///OUT endpoint interrupt
        ///bits
        oepint: u16 = 0,
    };
    ///OTG_FS all endpoints interrupt mask register
    ///(OTG_FS_DAINTMSK)
    pub const fs_daintmsk = Register(fs_daintmsk_val).init(0x50000800 + 0x1C);

    //////////////////////////
    ///DVBUSDIS
    const dvbusdis_val = packed struct {
        ///VBUSDT [0:15]
        ///Device VBUS discharge time
        vbusdt: u16 = 6103,
        _unused16: u16 = 0,
    };
    ///OTG_FS device VBUS discharge time
    ///register
    pub const dvbusdis = Register(dvbusdis_val).init(0x50000800 + 0x28);

    //////////////////////////
    ///DVBUSPULSE
    const dvbuspulse_val = packed struct {
        ///DVBUSP [0:11]
        ///Device VBUS pulsing time
        dvbusp: u12 = 1464,
        _unused12: u20 = 0,
    };
    ///OTG_FS device VBUS pulsing time
    ///register
    pub const dvbuspulse = Register(dvbuspulse_val).init(0x50000800 + 0x2C);

    //////////////////////////
    ///DIEPEMPMSK
    const diepempmsk_val = packed struct {
        ///INEPTXFEM [0:15]
        ///IN EP Tx FIFO empty interrupt mask
        ///bits
        ineptxfem: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS device IN endpoint FIFO empty
    ///interrupt mask register
    pub const diepempmsk = Register(diepempmsk_val).init(0x50000800 + 0x34);

    //////////////////////////
    ///FS_DIEPCTL0
    const fs_diepctl0_val = packed struct {
        ///MPSIZ [0:1]
        ///Maximum packet size
        mpsiz: u2 = 0,
        _unused2: u13 = 0,
        ///USBAEP [15:15]
        ///USB active endpoint
        usbaep: u1 = 0,
        _unused16: u1 = 0,
        ///NAKSTS [17:17]
        ///NAK status
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        _unused20: u1 = 0,
        ///STALL [21:21]
        ///STALL handshake
        stall: u1 = 0,
        ///TXFNUM [22:25]
        ///TxFIFO number
        tx_fnum: u4 = 0,
        ///CNAK [26:26]
        ///Clear NAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///Set NAK
        snak: u1 = 0,
        _unused28: u2 = 0,
        ///EPDIS [30:30]
        ///Endpoint disable
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///Endpoint enable
        epena: u1 = 0,
    };
    ///OTG_FS device control IN endpoint 0 control
    ///register (OTG_FS_DIEPCTL0)
    pub const fs_diepctl0 = Register(fs_diepctl0_val).init(0x50000800 + 0x100);

    //////////////////////////
    ///DIEPCTL1
    const diepctl1_val = packed struct {
        ///MPSIZ [0:10]
        ///MPSIZ
        mpsiz: u11 = 0,
        _unused11: u4 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 0,
        ///EONUM_DPID [16:16]
        ///EONUM/DPID
        eonum_dpid: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        _unused20: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        ///TXFNUM [22:25]
        ///TXFNUM
        tx_fnum: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        ///SD0PID_SEVNFRM [28:28]
        ///SD0PID/SEVNFRM
        sd0pid_sevnfrm: u1 = 0,
        ///SODDFRM_SD1PID [29:29]
        ///SODDFRM/SD1PID
        soddfrm_sd1pid: u1 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///OTG device endpoint-1 control
    ///register
    pub const diepctl1 = Register(diepctl1_val).init(0x50000800 + 0x120);

    //////////////////////////
    ///DIEPCTL2
    const diepctl2_val = packed struct {
        ///MPSIZ [0:10]
        ///MPSIZ
        mpsiz: u11 = 0,
        _unused11: u4 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 0,
        ///EONUM_DPID [16:16]
        ///EONUM/DPID
        eonum_dpid: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        _unused20: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        ///TXFNUM [22:25]
        ///TXFNUM
        tx_fnum: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        ///SD0PID_SEVNFRM [28:28]
        ///SD0PID/SEVNFRM
        sd0pid_sevnfrm: u1 = 0,
        ///SODDFRM [29:29]
        ///SODDFRM
        soddfrm: u1 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///OTG device endpoint-2 control
    ///register
    pub const diepctl2 = Register(diepctl2_val).init(0x50000800 + 0x140);

    //////////////////////////
    ///DIEPCTL3
    const diepctl3_val = packed struct {
        ///MPSIZ [0:10]
        ///MPSIZ
        mpsiz: u11 = 0,
        _unused11: u4 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 0,
        ///EONUM_DPID [16:16]
        ///EONUM/DPID
        eonum_dpid: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        _unused20: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        ///TXFNUM [22:25]
        ///TXFNUM
        tx_fnum: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        ///SD0PID_SEVNFRM [28:28]
        ///SD0PID/SEVNFRM
        sd0pid_sevnfrm: u1 = 0,
        ///SODDFRM [29:29]
        ///SODDFRM
        soddfrm: u1 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///OTG device endpoint-3 control
    ///register
    pub const diepctl3 = Register(diepctl3_val).init(0x50000800 + 0x160);

    //////////////////////////
    ///DOEPCTL0
    const doepctl0_val = packed struct {
        ///MPSIZ [0:1]
        ///MPSIZ
        mpsiz: u2 = 0,
        _unused2: u13 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 1,
        _unused16: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        ///SNPM [20:20]
        ///SNPM
        snpm: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        _unused22: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        _unused28: u2 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///device endpoint-0 control
    ///register
    pub const doepctl0 = Register(doepctl0_val).init(0x50000800 + 0x300);

    //////////////////////////
    ///DOEPCTL1
    const doepctl1_val = packed struct {
        ///MPSIZ [0:10]
        ///MPSIZ
        mpsiz: u11 = 0,
        _unused11: u4 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 0,
        ///EONUM_DPID [16:16]
        ///EONUM/DPID
        eonum_dpid: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        ///SNPM [20:20]
        ///SNPM
        snpm: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        _unused22: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        ///SD0PID_SEVNFRM [28:28]
        ///SD0PID/SEVNFRM
        sd0pid_sevnfrm: u1 = 0,
        ///SODDFRM [29:29]
        ///SODDFRM
        soddfrm: u1 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///device endpoint-1 control
    ///register
    pub const doepctl1 = Register(doepctl1_val).init(0x50000800 + 0x320);

    //////////////////////////
    ///DOEPCTL2
    const doepctl2_val = packed struct {
        ///MPSIZ [0:10]
        ///MPSIZ
        mpsiz: u11 = 0,
        _unused11: u4 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 0,
        ///EONUM_DPID [16:16]
        ///EONUM/DPID
        eonum_dpid: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        ///SNPM [20:20]
        ///SNPM
        snpm: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        _unused22: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        ///SD0PID_SEVNFRM [28:28]
        ///SD0PID/SEVNFRM
        sd0pid_sevnfrm: u1 = 0,
        ///SODDFRM [29:29]
        ///SODDFRM
        soddfrm: u1 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///device endpoint-2 control
    ///register
    pub const doepctl2 = Register(doepctl2_val).init(0x50000800 + 0x340);

    //////////////////////////
    ///DOEPCTL3
    const doepctl3_val = packed struct {
        ///MPSIZ [0:10]
        ///MPSIZ
        mpsiz: u11 = 0,
        _unused11: u4 = 0,
        ///USBAEP [15:15]
        ///USBAEP
        usbaep: u1 = 0,
        ///EONUM_DPID [16:16]
        ///EONUM/DPID
        eonum_dpid: u1 = 0,
        ///NAKSTS [17:17]
        ///NAKSTS
        naksts: u1 = 0,
        ///EPTYP [18:19]
        ///EPTYP
        eptyp: u2 = 0,
        ///SNPM [20:20]
        ///SNPM
        snpm: u1 = 0,
        ///Stall [21:21]
        ///Stall
        stall: u1 = 0,
        _unused22: u4 = 0,
        ///CNAK [26:26]
        ///CNAK
        cnak: u1 = 0,
        ///SNAK [27:27]
        ///SNAK
        snak: u1 = 0,
        ///SD0PID_SEVNFRM [28:28]
        ///SD0PID/SEVNFRM
        sd0pid_sevnfrm: u1 = 0,
        ///SODDFRM [29:29]
        ///SODDFRM
        soddfrm: u1 = 0,
        ///EPDIS [30:30]
        ///EPDIS
        epdis: u1 = 0,
        ///EPENA [31:31]
        ///EPENA
        epena: u1 = 0,
    };
    ///device endpoint-3 control
    ///register
    pub const doepctl3 = Register(doepctl3_val).init(0x50000800 + 0x360);

    //////////////////////////
    ///DIEPINT0
    const diepint0_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///TOC [3:3]
        ///TOC
        toc: u1 = 0,
        ///ITTXFE [4:4]
        ///ITTXFE
        ittxfe: u1 = 0,
        _unused5: u1 = 0,
        ///INEPNE [6:6]
        ///INEPNE
        inepne: u1 = 0,
        ///TXFE [7:7]
        ///TXFE
        txfe: u1 = 1,
        _unused8: u24 = 0,
    };
    ///device endpoint-x interrupt
    ///register
    pub const diepint0 = Register(diepint0_val).init(0x50000800 + 0x108);

    //////////////////////////
    ///DIEPINT1
    const diepint1_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///TOC [3:3]
        ///TOC
        toc: u1 = 0,
        ///ITTXFE [4:4]
        ///ITTXFE
        ittxfe: u1 = 0,
        _unused5: u1 = 0,
        ///INEPNE [6:6]
        ///INEPNE
        inepne: u1 = 0,
        ///TXFE [7:7]
        ///TXFE
        txfe: u1 = 1,
        _unused8: u24 = 0,
    };
    ///device endpoint-1 interrupt
    ///register
    pub const diepint1 = Register(diepint1_val).init(0x50000800 + 0x128);

    //////////////////////////
    ///DIEPINT2
    const diepint2_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///TOC [3:3]
        ///TOC
        toc: u1 = 0,
        ///ITTXFE [4:4]
        ///ITTXFE
        ittxfe: u1 = 0,
        _unused5: u1 = 0,
        ///INEPNE [6:6]
        ///INEPNE
        inepne: u1 = 0,
        ///TXFE [7:7]
        ///TXFE
        txfe: u1 = 1,
        _unused8: u24 = 0,
    };
    ///device endpoint-2 interrupt
    ///register
    pub const diepint2 = Register(diepint2_val).init(0x50000800 + 0x148);

    //////////////////////////
    ///DIEPINT3
    const diepint3_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///TOC [3:3]
        ///TOC
        toc: u1 = 0,
        ///ITTXFE [4:4]
        ///ITTXFE
        ittxfe: u1 = 0,
        _unused5: u1 = 0,
        ///INEPNE [6:6]
        ///INEPNE
        inepne: u1 = 0,
        ///TXFE [7:7]
        ///TXFE
        txfe: u1 = 1,
        _unused8: u24 = 0,
    };
    ///device endpoint-3 interrupt
    ///register
    pub const diepint3 = Register(diepint3_val).init(0x50000800 + 0x168);

    //////////////////////////
    ///DOEPINT0
    const doepint0_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///STUP [3:3]
        ///STUP
        stup: u1 = 0,
        ///OTEPDIS [4:4]
        ///OTEPDIS
        otepdis: u1 = 0,
        _unused5: u1 = 0,
        ///B2BSTUP [6:6]
        ///B2BSTUP
        b2bstup: u1 = 0,
        _unused7: u25 = 0,
    };
    ///device endpoint-0 interrupt
    ///register
    pub const doepint0 = Register(doepint0_val).init(0x50000800 + 0x308);

    //////////////////////////
    ///DOEPINT1
    const doepint1_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///STUP [3:3]
        ///STUP
        stup: u1 = 0,
        ///OTEPDIS [4:4]
        ///OTEPDIS
        otepdis: u1 = 0,
        _unused5: u1 = 0,
        ///B2BSTUP [6:6]
        ///B2BSTUP
        b2bstup: u1 = 0,
        _unused7: u25 = 0,
    };
    ///device endpoint-1 interrupt
    ///register
    pub const doepint1 = Register(doepint1_val).init(0x50000800 + 0x328);

    //////////////////////////
    ///DOEPINT2
    const doepint2_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///STUP [3:3]
        ///STUP
        stup: u1 = 0,
        ///OTEPDIS [4:4]
        ///OTEPDIS
        otepdis: u1 = 0,
        _unused5: u1 = 0,
        ///B2BSTUP [6:6]
        ///B2BSTUP
        b2bstup: u1 = 0,
        _unused7: u25 = 0,
    };
    ///device endpoint-2 interrupt
    ///register
    pub const doepint2 = Register(doepint2_val).init(0x50000800 + 0x348);

    //////////////////////////
    ///DOEPINT3
    const doepint3_val = packed struct {
        ///XFRC [0:0]
        ///XFRC
        xfrc: u1 = 0,
        ///EPDISD [1:1]
        ///EPDISD
        epdisd: u1 = 0,
        _unused2: u1 = 0,
        ///STUP [3:3]
        ///STUP
        stup: u1 = 0,
        ///OTEPDIS [4:4]
        ///OTEPDIS
        otepdis: u1 = 0,
        _unused5: u1 = 0,
        ///B2BSTUP [6:6]
        ///B2BSTUP
        b2bstup: u1 = 0,
        _unused7: u25 = 0,
    };
    ///device endpoint-3 interrupt
    ///register
    pub const doepint3 = Register(doepint3_val).init(0x50000800 + 0x368);

    //////////////////////////
    ///DIEPTSIZ0
    const dieptsiz0_val = packed struct {
        ///XFRSIZ [0:6]
        ///Transfer size
        xfrsiz: u7 = 0,
        _unused7: u12 = 0,
        ///PKTCNT [19:20]
        ///Packet count
        pktcnt: u2 = 0,
        _unused21: u11 = 0,
    };
    ///device endpoint-0 transfer size
    ///register
    pub const dieptsiz0 = Register(dieptsiz0_val).init(0x50000800 + 0x110);

    //////////////////////////
    ///DOEPTSIZ0
    const doeptsiz0_val = packed struct {
        ///XFRSIZ [0:6]
        ///Transfer size
        xfrsiz: u7 = 0,
        _unused7: u12 = 0,
        ///PKTCNT [19:19]
        ///Packet count
        pktcnt: u1 = 0,
        _unused20: u9 = 0,
        ///STUPCNT [29:30]
        ///SETUP packet count
        stupcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device OUT endpoint-0 transfer size
    ///register
    pub const doeptsiz0 = Register(doeptsiz0_val).init(0x50000800 + 0x310);

    //////////////////////////
    ///DIEPTSIZ1
    const dieptsiz1_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///MCNT [29:30]
        ///Multi count
        mcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device endpoint-1 transfer size
    ///register
    pub const dieptsiz1 = Register(dieptsiz1_val).init(0x50000800 + 0x130);

    //////////////////////////
    ///DIEPTSIZ2
    const dieptsiz2_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///MCNT [29:30]
        ///Multi count
        mcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device endpoint-2 transfer size
    ///register
    pub const dieptsiz2 = Register(dieptsiz2_val).init(0x50000800 + 0x150);

    //////////////////////////
    ///DIEPTSIZ3
    const dieptsiz3_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///MCNT [29:30]
        ///Multi count
        mcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device endpoint-3 transfer size
    ///register
    pub const dieptsiz3 = Register(dieptsiz3_val).init(0x50000800 + 0x170);

    //////////////////////////
    ///DTXFSTS0
    const dtxfsts0_val = packed struct {
        ///INEPTFSAV [0:15]
        ///IN endpoint TxFIFO space
        ///available
        ineptfsav: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS device IN endpoint transmit FIFO
    ///status register
    pub const dtxfsts0 = RegisterRW(dtxfsts0_val, void).init(0x50000800 + 0x118);

    //////////////////////////
    ///DTXFSTS1
    const dtxfsts1_val = packed struct {
        ///INEPTFSAV [0:15]
        ///IN endpoint TxFIFO space
        ///available
        ineptfsav: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS device IN endpoint transmit FIFO
    ///status register
    pub const dtxfsts1 = RegisterRW(dtxfsts1_val, void).init(0x50000800 + 0x138);

    //////////////////////////
    ///DTXFSTS2
    const dtxfsts2_val = packed struct {
        ///INEPTFSAV [0:15]
        ///IN endpoint TxFIFO space
        ///available
        ineptfsav: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS device IN endpoint transmit FIFO
    ///status register
    pub const dtxfsts2 = RegisterRW(dtxfsts2_val, void).init(0x50000800 + 0x158);

    //////////////////////////
    ///DTXFSTS3
    const dtxfsts3_val = packed struct {
        ///INEPTFSAV [0:15]
        ///IN endpoint TxFIFO space
        ///available
        ineptfsav: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS device IN endpoint transmit FIFO
    ///status register
    pub const dtxfsts3 = RegisterRW(dtxfsts3_val, void).init(0x50000800 + 0x178);

    //////////////////////////
    ///DOEPTSIZ1
    const doeptsiz1_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///RXDPID_STUPCNT [29:30]
        ///Received data PID/SETUP packet
        ///count
        rxdpid_stupcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device OUT endpoint-1 transfer size
    ///register
    pub const doeptsiz1 = Register(doeptsiz1_val).init(0x50000800 + 0x330);

    //////////////////////////
    ///DOEPTSIZ2
    const doeptsiz2_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///RXDPID_STUPCNT [29:30]
        ///Received data PID/SETUP packet
        ///count
        rxdpid_stupcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device OUT endpoint-2 transfer size
    ///register
    pub const doeptsiz2 = Register(doeptsiz2_val).init(0x50000800 + 0x350);

    //////////////////////////
    ///DOEPTSIZ3
    const doeptsiz3_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///RXDPID_STUPCNT [29:30]
        ///Received data PID/SETUP packet
        ///count
        rxdpid_stupcnt: u2 = 0,
        _unused31: u1 = 0,
    };
    ///device OUT endpoint-3 transfer size
    ///register
    pub const doeptsiz3 = Register(doeptsiz3_val).init(0x50000800 + 0x370);
};

///USB on the go full speed
pub const otg_fs_global = struct {

    //////////////////////////
    ///FS_GOTGCTL
    const fs_gotgctl_val = packed struct {
        ///SRQSCS [0:0]
        ///Session request success
        srqscs: u1 = 0,
        ///SRQ [1:1]
        ///Session request
        srq: u1 = 0,
        _unused2: u6 = 0,
        ///HNGSCS [8:8]
        ///Host negotiation success
        hngscs: u1 = 0,
        ///HNPRQ [9:9]
        ///HNP request
        hnprq: u1 = 0,
        ///HSHNPEN [10:10]
        ///Host set HNP enable
        hshnpen: u1 = 0,
        ///DHNPEN [11:11]
        ///Device HNP enabled
        dhnpen: u1 = 1,
        _unused12: u4 = 0,
        ///CIDSTS [16:16]
        ///Connector ID status
        cidsts: u1 = 0,
        ///DBCT [17:17]
        ///Long/short debounce time
        dbct: u1 = 0,
        ///ASVLD [18:18]
        ///A-session valid
        asvld: u1 = 0,
        ///BSVLD [19:19]
        ///B-session valid
        bsvld: u1 = 0,
        _unused20: u12 = 0,
    };
    ///OTG_FS control and status register
    ///(OTG_FS_GOTGCTL)
    pub const fs_gotgctl = Register(fs_gotgctl_val).init(0x50000000 + 0x0);

    //////////////////////////
    ///FS_GOTGINT
    const fs_gotgint_val = packed struct {
        _unused0: u2 = 0,
        ///SEDET [2:2]
        ///Session end detected
        sedet: u1 = 0,
        _unused3: u5 = 0,
        ///SRSSCHG [8:8]
        ///Session request success status
        ///change
        srsschg: u1 = 0,
        ///HNSSCHG [9:9]
        ///Host negotiation success status
        ///change
        hnsschg: u1 = 0,
        _unused10: u7 = 0,
        ///HNGDET [17:17]
        ///Host negotiation detected
        hngdet: u1 = 0,
        ///ADTOCHG [18:18]
        ///A-device timeout change
        adtochg: u1 = 0,
        ///DBCDNE [19:19]
        ///Debounce done
        dbcdne: u1 = 0,
        _unused20: u12 = 0,
    };
    ///OTG_FS interrupt register
    ///(OTG_FS_GOTGINT)
    pub const fs_gotgint = Register(fs_gotgint_val).init(0x50000000 + 0x4);

    //////////////////////////
    ///FS_GAHBCFG
    const fs_gahbcfg_val = packed struct {
        ///GINT [0:0]
        ///Global interrupt mask
        gint: u1 = 0,
        _unused1: u6 = 0,
        ///TXFELVL [7:7]
        ///TxFIFO empty level
        txfelvl: u1 = 0,
        ///PTXFELVL [8:8]
        ///Periodic TxFIFO empty
        ///level
        ptxfelvl: u1 = 0,
        _unused9: u23 = 0,
    };
    ///OTG_FS AHB configuration register
    ///(OTG_FS_GAHBCFG)
    pub const fs_gahbcfg = Register(fs_gahbcfg_val).init(0x50000000 + 0x8);

    //////////////////////////
    ///FS_GUSBCFG
    const fs_gusbcfg_val = packed struct {
        ///TOCAL [0:2]
        ///FS timeout calibration
        tocal: u3 = 0,
        _unused3: u3 = 0,
        ///PHYSEL [6:6]
        ///Full Speed serial transceiver
        ///select
        physel: u1 = 0,
        _unused7: u1 = 0,
        ///SRPCAP [8:8]
        ///SRP-capable
        srpcap: u1 = 0,
        ///HNPCAP [9:9]
        ///HNP-capable
        hnpcap: u1 = 1,
        ///TRDT [10:13]
        ///USB turnaround time
        trdt: u4 = 2,
        _unused14: u15 = 0,
        ///FHMOD [29:29]
        ///Force host mode
        fhmod: u1 = 0,
        ///FDMOD [30:30]
        ///Force device mode
        fdmod: u1 = 0,
        ///CTXPKT [31:31]
        ///Corrupt Tx packet
        ctxpkt: u1 = 0,
    };
    ///OTG_FS USB configuration register
    ///(OTG_FS_GUSBCFG)
    pub const fs_gusbcfg = Register(fs_gusbcfg_val).init(0x50000000 + 0xC);

    //////////////////////////
    ///FS_GRSTCTL
    const fs_grstctl_val = packed struct {
        ///CSRST [0:0]
        ///Core soft reset
        csrst: u1 = 0,
        ///HSRST [1:1]
        ///HCLK soft reset
        hsrst: u1 = 0,
        ///FCRST [2:2]
        ///Host frame counter reset
        fcrst: u1 = 0,
        _unused3: u1 = 0,
        ///RXFFLSH [4:4]
        ///RxFIFO flush
        rxfflsh: u1 = 0,
        ///TXFFLSH [5:5]
        ///TxFIFO flush
        txfflsh: u1 = 0,
        ///TXFNUM [6:10]
        ///TxFIFO number
        tx_fnum: u5 = 0,
        _unused11: u20 = 0,
        ///AHBIDL [31:31]
        ///AHB master idle
        ahbidl: u1 = 0,
    };
    ///OTG_FS reset register
    ///(OTG_FS_GRSTCTL)
    pub const fs_grstctl = Register(fs_grstctl_val).init(0x50000000 + 0x10);

    //////////////////////////
    ///FS_GINTSTS
    const fs_gintsts_val = packed struct {
        ///CMOD [0:0]
        ///Current mode of operation
        cmod: u1 = 0,
        ///MMIS [1:1]
        ///Mode mismatch interrupt
        mmis: u1 = 0,
        ///OTGINT [2:2]
        ///OTG interrupt
        otgint: u1 = 0,
        ///SOF [3:3]
        ///Start of frame
        sof: u1 = 0,
        ///RXFLVL [4:4]
        ///RxFIFO non-empty
        rxflvl: u1 = 0,
        ///NPTXFE [5:5]
        ///Non-periodic TxFIFO empty
        nptxfe: u1 = 1,
        ///GINAKEFF [6:6]
        ///Global IN non-periodic NAK
        ///effective
        ginakeff: u1 = 0,
        ///GOUTNAKEFF [7:7]
        ///Global OUT NAK effective
        goutnakeff: u1 = 0,
        _unused8: u2 = 0,
        ///ESUSP [10:10]
        ///Early suspend
        esusp: u1 = 0,
        ///USBSUSP [11:11]
        ///USB suspend
        usbsusp: u1 = 0,
        ///USBRST [12:12]
        ///USB reset
        usbrst: u1 = 0,
        ///ENUMDNE [13:13]
        ///Enumeration done
        enumdne: u1 = 0,
        ///ISOODRP [14:14]
        ///Isochronous OUT packet dropped
        ///interrupt
        isoodrp: u1 = 0,
        ///EOPF [15:15]
        ///End of periodic frame
        ///interrupt
        eopf: u1 = 0,
        _unused16: u2 = 0,
        ///IEPINT [18:18]
        ///IN endpoint interrupt
        iepint: u1 = 0,
        ///OEPINT [19:19]
        ///OUT endpoint interrupt
        oepint: u1 = 0,
        ///IISOIXFR [20:20]
        ///Incomplete isochronous IN
        ///transfer
        iisoixfr: u1 = 0,
        ///IPXFR_INCOMPISOOUT [21:21]
        ///Incomplete periodic transfer(Host
        ///mode)/Incomplete isochronous OUT transfer(Device
        ///mode)
        ipxfr_incompisoout: u1 = 0,
        _unused22: u2 = 0,
        ///HPRTINT [24:24]
        ///Host port interrupt
        hprtint: u1 = 0,
        ///HCINT [25:25]
        ///Host channels interrupt
        hcint: u1 = 0,
        ///PTXFE [26:26]
        ///Periodic TxFIFO empty
        ptxfe: u1 = 1,
        _unused27: u1 = 0,
        ///CIDSCHG [28:28]
        ///Connector ID status change
        cidschg: u1 = 0,
        ///DISCINT [29:29]
        ///Disconnect detected
        ///interrupt
        discint: u1 = 0,
        ///SRQINT [30:30]
        ///Session request/new session detected
        ///interrupt
        srqint: u1 = 0,
        ///WKUPINT [31:31]
        ///Resume/remote wakeup detected
        ///interrupt
        wkupint: u1 = 0,
    };
    ///OTG_FS core interrupt register
    ///(OTG_FS_GINTSTS)
    pub const fs_gintsts = Register(fs_gintsts_val).init(0x50000000 + 0x14);

    //////////////////////////
    ///FS_GINTMSK
    const fs_gintmsk_val = packed struct {
        _unused0: u1 = 0,
        ///MMISM [1:1]
        ///Mode mismatch interrupt
        ///mask
        mmism: u1 = 0,
        ///OTGINT [2:2]
        ///OTG interrupt mask
        otgint: u1 = 0,
        ///SOFM [3:3]
        ///Start of frame mask
        sofm: u1 = 0,
        ///RXFLVLM [4:4]
        ///Receive FIFO non-empty
        ///mask
        rxflvlm: u1 = 0,
        ///NPTXFEM [5:5]
        ///Non-periodic TxFIFO empty
        ///mask
        nptxfem: u1 = 0,
        ///GINAKEFFM [6:6]
        ///Global non-periodic IN NAK effective
        ///mask
        ginakeffm: u1 = 0,
        ///GONAKEFFM [7:7]
        ///Global OUT NAK effective
        ///mask
        gonakeffm: u1 = 0,
        _unused8: u2 = 0,
        ///ESUSPM [10:10]
        ///Early suspend mask
        esuspm: u1 = 0,
        ///USBSUSPM [11:11]
        ///USB suspend mask
        usbsuspm: u1 = 0,
        ///USBRST [12:12]
        ///USB reset mask
        usbrst: u1 = 0,
        ///ENUMDNEM [13:13]
        ///Enumeration done mask
        enumdnem: u1 = 0,
        ///ISOODRPM [14:14]
        ///Isochronous OUT packet dropped interrupt
        ///mask
        isoodrpm: u1 = 0,
        ///EOPFM [15:15]
        ///End of periodic frame interrupt
        ///mask
        eopfm: u1 = 0,
        _unused16: u1 = 0,
        ///EPMISM [17:17]
        ///Endpoint mismatch interrupt
        ///mask
        epmism: u1 = 0,
        ///IEPINT [18:18]
        ///IN endpoints interrupt
        ///mask
        iepint: u1 = 0,
        ///OEPINT [19:19]
        ///OUT endpoints interrupt
        ///mask
        oepint: u1 = 0,
        ///IISOIXFRM [20:20]
        ///Incomplete isochronous IN transfer
        ///mask
        iisoixfrm: u1 = 0,
        ///IPXFRM_IISOOXFRM [21:21]
        ///Incomplete periodic transfer mask(Host
        ///mode)/Incomplete isochronous OUT transfer mask(Device
        ///mode)
        ipxfrm_iisooxfrm: u1 = 0,
        _unused22: u2 = 0,
        ///PRTIM [24:24]
        ///Host port interrupt mask
        prtim: u1 = 0,
        ///HCIM [25:25]
        ///Host channels interrupt
        ///mask
        hcim: u1 = 0,
        ///PTXFEM [26:26]
        ///Periodic TxFIFO empty mask
        ptxfem: u1 = 0,
        _unused27: u1 = 0,
        ///CIDSCHGM [28:28]
        ///Connector ID status change
        ///mask
        cidschgm: u1 = 0,
        ///DISCINT [29:29]
        ///Disconnect detected interrupt
        ///mask
        discint: u1 = 0,
        ///SRQIM [30:30]
        ///Session request/new session detected
        ///interrupt mask
        srqim: u1 = 0,
        ///WUIM [31:31]
        ///Resume/remote wakeup detected interrupt
        ///mask
        wuim: u1 = 0,
    };
    ///OTG_FS interrupt mask register
    ///(OTG_FS_GINTMSK)
    pub const fs_gintmsk = Register(fs_gintmsk_val).init(0x50000000 + 0x18);

    //////////////////////////
    ///FS_GRXSTSR_Device
    const fs_grxstsr_device_val = packed struct {
        ///EPNUM [0:3]
        ///Endpoint number
        epnum: u4 = 0,
        ///BCNT [4:14]
        ///Byte count
        bcnt: u11 = 0,
        ///DPID [15:16]
        ///Data PID
        dpid: u2 = 0,
        ///PKTSTS [17:20]
        ///Packet status
        pktsts: u4 = 0,
        ///FRMNUM [21:24]
        ///Frame number
        frmnum: u4 = 0,
        _unused25: u7 = 0,
    };
    ///OTG_FS Receive status debug read(Device
    ///mode)
    pub const fs_grxstsr_device = RegisterRW(fs_grxstsr_device_val, void).init(0x50000000 + 0x1C);

    //////////////////////////
    ///FS_GRXSTSR_Host
    const fs_grxstsr_host_val = packed struct {
        ///EPNUM [0:3]
        ///Endpoint number
        epnum: u4 = 0,
        ///BCNT [4:14]
        ///Byte count
        bcnt: u11 = 0,
        ///DPID [15:16]
        ///Data PID
        dpid: u2 = 0,
        ///PKTSTS [17:20]
        ///Packet status
        pktsts: u4 = 0,
        ///FRMNUM [21:24]
        ///Frame number
        frmnum: u4 = 0,
        _unused25: u7 = 0,
    };
    ///OTG_FS Receive status debug read(Host
    ///mode)
    pub const fs_grxstsr_host = RegisterRW(fs_grxstsr_host_val, void).init(0x50000000 + 0x1C);

    //////////////////////////
    ///FS_GRXFSIZ
    const fs_grxfsiz_val = packed struct {
        ///RXFD [0:15]
        ///RxFIFO depth
        rxfd: u16 = 512,
        _unused16: u16 = 0,
    };
    ///OTG_FS Receive FIFO size register
    ///(OTG_FS_GRXFSIZ)
    pub const fs_grxfsiz = Register(fs_grxfsiz_val).init(0x50000000 + 0x24);

    //////////////////////////
    ///FS_GNPTXFSIZ_Device
    const fs_gnptxfsiz_device_val = packed struct {
        ///TX0FSA [0:15]
        ///Endpoint 0 transmit RAM start
        ///address
        tx0fsa: u16 = 512,
        ///TX0FD [16:31]
        ///Endpoint 0 TxFIFO depth
        tx0fd: u16 = 0,
    };
    ///OTG_FS non-periodic transmit FIFO size
    ///register (Device mode)
    pub const fs_gnptxfsiz_device = Register(fs_gnptxfsiz_device_val).init(0x50000000 + 0x28);

    //////////////////////////
    ///FS_GNPTXFSIZ_Host
    const fs_gnptxfsiz_host_val = packed struct {
        ///NPTXFSA [0:15]
        ///Non-periodic transmit RAM start
        ///address
        nptxfsa: u16 = 512,
        ///NPTXFD [16:31]
        ///Non-periodic TxFIFO depth
        nptxfd: u16 = 0,
    };
    ///OTG_FS non-periodic transmit FIFO size
    ///register (Host mode)
    pub const fs_gnptxfsiz_host = Register(fs_gnptxfsiz_host_val).init(0x50000000 + 0x28);

    //////////////////////////
    ///FS_GNPTXSTS
    const fs_gnptxsts_val = packed struct {
        ///NPTXFSAV [0:15]
        ///Non-periodic TxFIFO space
        ///available
        nptxfsav: u16 = 512,
        ///NPTQXSAV [16:23]
        ///Non-periodic transmit request queue
        ///space available
        nptqxsav: u8 = 8,
        ///NPTXQTOP [24:30]
        ///Top of the non-periodic transmit request
        ///queue
        nptxqtop: u7 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS non-periodic transmit FIFO/queue
    ///status register (OTG_FS_GNPTXSTS)
    pub const fs_gnptxsts = RegisterRW(fs_gnptxsts_val, void).init(0x50000000 + 0x2C);

    //////////////////////////
    ///FS_GCCFG
    const fs_gccfg_val = packed struct {
        _unused0: u16 = 0,
        ///PWRDWN [16:16]
        ///Power down
        pwrdwn: u1 = 0,
        _unused17: u1 = 0,
        ///VBUSASEN [18:18]
        ///Enable the VBUS sensing
        ///device
        vbusasen: u1 = 0,
        ///VBUSBSEN [19:19]
        ///Enable the VBUS sensing
        ///device
        vbusbsen: u1 = 0,
        ///SOFOUTEN [20:20]
        ///SOF output enable
        sofouten: u1 = 0,
        _unused21: u11 = 0,
    };
    ///OTG_FS general core configuration register
    ///(OTG_FS_GCCFG)
    pub const fs_gccfg = Register(fs_gccfg_val).init(0x50000000 + 0x38);

    //////////////////////////
    ///FS_CID
    const fs_cid_val = packed struct {
        ///PRODUCT_ID [0:31]
        ///Product ID field
        product_id: u32 = 4096,
    };
    ///core ID register
    pub const fs_cid = Register(fs_cid_val).init(0x50000000 + 0x3C);

    //////////////////////////
    ///FS_HPTXFSIZ
    const fs_hptxfsiz_val = packed struct {
        ///PTXSA [0:15]
        ///Host periodic TxFIFO start
        ///address
        ptxsa: u16 = 1536,
        ///PTXFSIZ [16:31]
        ///Host periodic TxFIFO depth
        ptxfsiz: u16 = 512,
    };
    ///OTG_FS Host periodic transmit FIFO size
    ///register (OTG_FS_HPTXFSIZ)
    pub const fs_hptxfsiz = Register(fs_hptxfsiz_val).init(0x50000000 + 0x100);

    //////////////////////////
    ///FS_DIEPTXF1
    const fs_dieptxf1_val = packed struct {
        ///INEPTXSA [0:15]
        ///IN endpoint FIFO2 transmit RAM start
        ///address
        ineptxsa: u16 = 1024,
        ///INEPTXFD [16:31]
        ///IN endpoint TxFIFO depth
        ineptxfd: u16 = 512,
    };
    ///OTG_FS device IN endpoint transmit FIFO size
    ///register (OTG_FS_DIEPTXF2)
    pub const fs_dieptxf1 = Register(fs_dieptxf1_val).init(0x50000000 + 0x104);

    //////////////////////////
    ///FS_DIEPTXF2
    const fs_dieptxf2_val = packed struct {
        ///INEPTXSA [0:15]
        ///IN endpoint FIFO3 transmit RAM start
        ///address
        ineptxsa: u16 = 1024,
        ///INEPTXFD [16:31]
        ///IN endpoint TxFIFO depth
        ineptxfd: u16 = 512,
    };
    ///OTG_FS device IN endpoint transmit FIFO size
    ///register (OTG_FS_DIEPTXF3)
    pub const fs_dieptxf2 = Register(fs_dieptxf2_val).init(0x50000000 + 0x108);

    //////////////////////////
    ///FS_DIEPTXF3
    const fs_dieptxf3_val = packed struct {
        ///INEPTXSA [0:15]
        ///IN endpoint FIFO4 transmit RAM start
        ///address
        ineptxsa: u16 = 1024,
        ///INEPTXFD [16:31]
        ///IN endpoint TxFIFO depth
        ineptxfd: u16 = 512,
    };
    ///OTG_FS device IN endpoint transmit FIFO size
    ///register (OTG_FS_DIEPTXF4)
    pub const fs_dieptxf3 = Register(fs_dieptxf3_val).init(0x50000000 + 0x10C);
};

///USB on the go full speed
pub const otg_fs_host = struct {

    //////////////////////////
    ///FS_HCFG
    const fs_hcfg_val = packed struct {
        ///FSLSPCS [0:1]
        ///FS/LS PHY clock select
        fslspcs: u2 = 0,
        ///FSLSS [2:2]
        ///FS- and LS-only support
        fslss: u1 = 0,
        _unused3: u29 = 0,
    };
    ///OTG_FS host configuration register
    ///(OTG_FS_HCFG)
    pub const fs_hcfg = Register(fs_hcfg_val).init(0x50000400 + 0x0);

    //////////////////////////
    ///HFIR
    const hfir_val = packed struct {
        ///FRIVL [0:15]
        ///Frame interval
        frivl: u16 = 60000,
        _unused16: u16 = 0,
    };
    ///OTG_FS Host frame interval
    ///register
    pub const hfir = Register(hfir_val).init(0x50000400 + 0x4);

    //////////////////////////
    ///FS_HFNUM
    const fs_h_fnum_val = packed struct {
        ///FRNUM [0:15]
        ///Frame number
        frnum: u16 = 16383,
        ///FTREM [16:31]
        ///Frame time remaining
        ftrem: u16 = 0,
    };
    ///OTG_FS host frame number/frame time
    ///remaining register (OTG_FS_HFNUM)
    pub const fs_h_fnum = RegisterRW(fs_h_fnum_val, void).init(0x50000400 + 0x8);

    //////////////////////////
    ///FS_HPTXSTS
    const fs_hptxsts_val = packed struct {
        ///PTXFSAVL [0:15]
        ///Periodic transmit data FIFO space
        ///available
        ptxfsavl: u16 = 256,
        ///PTXQSAV [16:23]
        ///Periodic transmit request queue space
        ///available
        ptxqsav: u8 = 8,
        ///PTXQTOP [24:31]
        ///Top of the periodic transmit request
        ///queue
        ptxqtop: u8 = 0,
    };
    ///OTG_FS_Host periodic transmit FIFO/queue
    ///status register (OTG_FS_HPTXSTS)
    pub const fs_hptxsts = Register(fs_hptxsts_val).init(0x50000400 + 0x10);

    //////////////////////////
    ///HAINT
    const haint_val = packed struct {
        ///HAINT [0:15]
        ///Channel interrupts
        haint: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS Host all channels interrupt
    ///register
    pub const haint = RegisterRW(haint_val, void).init(0x50000400 + 0x14);

    //////////////////////////
    ///HAINTMSK
    const haintmsk_val = packed struct {
        ///HAINTM [0:15]
        ///Channel interrupt mask
        haintm: u16 = 0,
        _unused16: u16 = 0,
    };
    ///OTG_FS host all channels interrupt mask
    ///register
    pub const haintmsk = Register(haintmsk_val).init(0x50000400 + 0x18);

    //////////////////////////
    ///FS_HPRT
    const fs_hprt_val = packed struct {
        ///PCSTS [0:0]
        ///Port connect status
        pcsts: u1 = 0,
        ///PCDET [1:1]
        ///Port connect detected
        pcdet: u1 = 0,
        ///PENA [2:2]
        ///Port enable
        pena: u1 = 0,
        ///PENCHNG [3:3]
        ///Port enable/disable change
        penchng: u1 = 0,
        ///POCA [4:4]
        ///Port overcurrent active
        poca: u1 = 0,
        ///POCCHNG [5:5]
        ///Port overcurrent change
        pocchng: u1 = 0,
        ///PRES [6:6]
        ///Port resume
        pres: u1 = 0,
        ///PSUSP [7:7]
        ///Port suspend
        psusp: u1 = 0,
        ///PRST [8:8]
        ///Port reset
        prst: u1 = 0,
        _unused9: u1 = 0,
        ///PLSTS [10:11]
        ///Port line status
        plsts: u2 = 0,
        ///PPWR [12:12]
        ///Port power
        ppwr: u1 = 0,
        ///PTCTL [13:16]
        ///Port test control
        ptctl: u4 = 0,
        ///PSPD [17:18]
        ///Port speed
        pspd: u2 = 0,
        _unused19: u13 = 0,
    };
    ///OTG_FS host port control and status register
    ///(OTG_FS_HPRT)
    pub const fs_hprt = Register(fs_hprt_val).init(0x50000400 + 0x40);

    //////////////////////////
    ///FS_HCCHAR0
    const fs_hcchar0_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-0 characteristics
    ///register (OTG_FS_HCCHAR0)
    pub const fs_hcchar0 = Register(fs_hcchar0_val).init(0x50000400 + 0x100);

    //////////////////////////
    ///FS_HCCHAR1
    const fs_hcchar1_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-1 characteristics
    ///register (OTG_FS_HCCHAR1)
    pub const fs_hcchar1 = Register(fs_hcchar1_val).init(0x50000400 + 0x120);

    //////////////////////////
    ///FS_HCCHAR2
    const fs_hcchar2_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-2 characteristics
    ///register (OTG_FS_HCCHAR2)
    pub const fs_hcchar2 = Register(fs_hcchar2_val).init(0x50000400 + 0x140);

    //////////////////////////
    ///FS_HCCHAR3
    const fs_hcchar3_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-3 characteristics
    ///register (OTG_FS_HCCHAR3)
    pub const fs_hcchar3 = Register(fs_hcchar3_val).init(0x50000400 + 0x160);

    //////////////////////////
    ///FS_HCCHAR4
    const fs_hcchar4_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-4 characteristics
    ///register (OTG_FS_HCCHAR4)
    pub const fs_hcchar4 = Register(fs_hcchar4_val).init(0x50000400 + 0x180);

    //////////////////////////
    ///FS_HCCHAR5
    const fs_hcchar5_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-5 characteristics
    ///register (OTG_FS_HCCHAR5)
    pub const fs_hcchar5 = Register(fs_hcchar5_val).init(0x50000400 + 0x1A0);

    //////////////////////////
    ///FS_HCCHAR6
    const fs_hcchar6_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-6 characteristics
    ///register (OTG_FS_HCCHAR6)
    pub const fs_hcchar6 = Register(fs_hcchar6_val).init(0x50000400 + 0x1C0);

    //////////////////////////
    ///FS_HCCHAR7
    const fs_hcchar7_val = packed struct {
        ///MPSIZ [0:10]
        ///Maximum packet size
        mpsiz: u11 = 0,
        ///EPNUM [11:14]
        ///Endpoint number
        epnum: u4 = 0,
        ///EPDIR [15:15]
        ///Endpoint direction
        epdir: u1 = 0,
        _unused16: u1 = 0,
        ///LSDEV [17:17]
        ///Low-speed device
        lsdev: u1 = 0,
        ///EPTYP [18:19]
        ///Endpoint type
        eptyp: u2 = 0,
        ///MCNT [20:21]
        ///Multicount
        mcnt: u2 = 0,
        ///DAD [22:28]
        ///Device address
        dad: u7 = 0,
        ///ODDFRM [29:29]
        ///Odd frame
        oddfrm: u1 = 0,
        ///CHDIS [30:30]
        ///Channel disable
        chdis: u1 = 0,
        ///CHENA [31:31]
        ///Channel enable
        chena: u1 = 0,
    };
    ///OTG_FS host channel-7 characteristics
    ///register (OTG_FS_HCCHAR7)
    pub const fs_hcchar7 = Register(fs_hcchar7_val).init(0x50000400 + 0x1E0);

    //////////////////////////
    ///FS_HCINT0
    const fs_hcint0_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-0 interrupt register
    ///(OTG_FS_HCINT0)
    pub const fs_hcint0 = Register(fs_hcint0_val).init(0x50000400 + 0x108);

    //////////////////////////
    ///FS_HCINT1
    const fs_hcint1_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-1 interrupt register
    ///(OTG_FS_HCINT1)
    pub const fs_hcint1 = Register(fs_hcint1_val).init(0x50000400 + 0x128);

    //////////////////////////
    ///FS_HCINT2
    const fs_hcint2_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-2 interrupt register
    ///(OTG_FS_HCINT2)
    pub const fs_hcint2 = Register(fs_hcint2_val).init(0x50000400 + 0x148);

    //////////////////////////
    ///FS_HCINT3
    const fs_hcint3_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-3 interrupt register
    ///(OTG_FS_HCINT3)
    pub const fs_hcint3 = Register(fs_hcint3_val).init(0x50000400 + 0x168);

    //////////////////////////
    ///FS_HCINT4
    const fs_hcint4_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-4 interrupt register
    ///(OTG_FS_HCINT4)
    pub const fs_hcint4 = Register(fs_hcint4_val).init(0x50000400 + 0x188);

    //////////////////////////
    ///FS_HCINT5
    const fs_hcint5_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-5 interrupt register
    ///(OTG_FS_HCINT5)
    pub const fs_hcint5 = Register(fs_hcint5_val).init(0x50000400 + 0x1A8);

    //////////////////////////
    ///FS_HCINT6
    const fs_hcint6_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-6 interrupt register
    ///(OTG_FS_HCINT6)
    pub const fs_hcint6 = Register(fs_hcint6_val).init(0x50000400 + 0x1C8);

    //////////////////////////
    ///FS_HCINT7
    const fs_hcint7_val = packed struct {
        ///XFRC [0:0]
        ///Transfer completed
        xfrc: u1 = 0,
        ///CHH [1:1]
        ///Channel halted
        chh: u1 = 0,
        _unused2: u1 = 0,
        ///STALL [3:3]
        ///STALL response received
        ///interrupt
        stall: u1 = 0,
        ///NAK [4:4]
        ///NAK response received
        ///interrupt
        nak: u1 = 0,
        ///ACK [5:5]
        ///ACK response received/transmitted
        ///interrupt
        ack: u1 = 0,
        _unused6: u1 = 0,
        ///TXERR [7:7]
        ///Transaction error
        txerr: u1 = 0,
        ///BBERR [8:8]
        ///Babble error
        bberr: u1 = 0,
        ///FRMOR [9:9]
        ///Frame overrun
        frmor: u1 = 0,
        ///DTERR [10:10]
        ///Data toggle error
        dterr: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-7 interrupt register
    ///(OTG_FS_HCINT7)
    pub const fs_hcint7 = Register(fs_hcint7_val).init(0x50000400 + 0x1E8);

    //////////////////////////
    ///FS_HCINTMSK0
    const fs_hcintmsk0_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-0 mask register
    ///(OTG_FS_HCINTMSK0)
    pub const fs_hcintmsk0 = Register(fs_hcintmsk0_val).init(0x50000400 + 0x10C);

    //////////////////////////
    ///FS_HCINTMSK1
    const fs_hcintmsk1_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-1 mask register
    ///(OTG_FS_HCINTMSK1)
    pub const fs_hcintmsk1 = Register(fs_hcintmsk1_val).init(0x50000400 + 0x12C);

    //////////////////////////
    ///FS_HCINTMSK2
    const fs_hcintmsk2_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-2 mask register
    ///(OTG_FS_HCINTMSK2)
    pub const fs_hcintmsk2 = Register(fs_hcintmsk2_val).init(0x50000400 + 0x14C);

    //////////////////////////
    ///FS_HCINTMSK3
    const fs_hcintmsk3_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-3 mask register
    ///(OTG_FS_HCINTMSK3)
    pub const fs_hcintmsk3 = Register(fs_hcintmsk3_val).init(0x50000400 + 0x16C);

    //////////////////////////
    ///FS_HCINTMSK4
    const fs_hcintmsk4_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-4 mask register
    ///(OTG_FS_HCINTMSK4)
    pub const fs_hcintmsk4 = Register(fs_hcintmsk4_val).init(0x50000400 + 0x18C);

    //////////////////////////
    ///FS_HCINTMSK5
    const fs_hcintmsk5_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-5 mask register
    ///(OTG_FS_HCINTMSK5)
    pub const fs_hcintmsk5 = Register(fs_hcintmsk5_val).init(0x50000400 + 0x1AC);

    //////////////////////////
    ///FS_HCINTMSK6
    const fs_hcintmsk6_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-6 mask register
    ///(OTG_FS_HCINTMSK6)
    pub const fs_hcintmsk6 = Register(fs_hcintmsk6_val).init(0x50000400 + 0x1CC);

    //////////////////////////
    ///FS_HCINTMSK7
    const fs_hcintmsk7_val = packed struct {
        ///XFRCM [0:0]
        ///Transfer completed mask
        xfrcm: u1 = 0,
        ///CHHM [1:1]
        ///Channel halted mask
        chhm: u1 = 0,
        _unused2: u1 = 0,
        ///STALLM [3:3]
        ///STALL response received interrupt
        ///mask
        stallm: u1 = 0,
        ///NAKM [4:4]
        ///NAK response received interrupt
        ///mask
        nakm: u1 = 0,
        ///ACKM [5:5]
        ///ACK response received/transmitted
        ///interrupt mask
        ackm: u1 = 0,
        ///NYET [6:6]
        ///response received interrupt
        ///mask
        nyet: u1 = 0,
        ///TXERRM [7:7]
        ///Transaction error mask
        txerrm: u1 = 0,
        ///BBERRM [8:8]
        ///Babble error mask
        bberrm: u1 = 0,
        ///FRMORM [9:9]
        ///Frame overrun mask
        frmorm: u1 = 0,
        ///DTERRM [10:10]
        ///Data toggle error mask
        dterrm: u1 = 0,
        _unused11: u21 = 0,
    };
    ///OTG_FS host channel-7 mask register
    ///(OTG_FS_HCINTMSK7)
    pub const fs_hcintmsk7 = Register(fs_hcintmsk7_val).init(0x50000400 + 0x1EC);

    //////////////////////////
    ///FS_HCTSIZ0
    const fs_hctsiz0_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-0 transfer size
    ///register
    pub const fs_hctsiz0 = Register(fs_hctsiz0_val).init(0x50000400 + 0x110);

    //////////////////////////
    ///FS_HCTSIZ1
    const fs_hctsiz1_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-1 transfer size
    ///register
    pub const fs_hctsiz1 = Register(fs_hctsiz1_val).init(0x50000400 + 0x130);

    //////////////////////////
    ///FS_HCTSIZ2
    const fs_hctsiz2_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-2 transfer size
    ///register
    pub const fs_hctsiz2 = Register(fs_hctsiz2_val).init(0x50000400 + 0x150);

    //////////////////////////
    ///FS_HCTSIZ3
    const fs_hctsiz3_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-3 transfer size
    ///register
    pub const fs_hctsiz3 = Register(fs_hctsiz3_val).init(0x50000400 + 0x170);

    //////////////////////////
    ///FS_HCTSIZ4
    const fs_hctsiz4_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-x transfer size
    ///register
    pub const fs_hctsiz4 = Register(fs_hctsiz4_val).init(0x50000400 + 0x190);

    //////////////////////////
    ///FS_HCTSIZ5
    const fs_hctsiz5_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-5 transfer size
    ///register
    pub const fs_hctsiz5 = Register(fs_hctsiz5_val).init(0x50000400 + 0x1B0);

    //////////////////////////
    ///FS_HCTSIZ6
    const fs_hctsiz6_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-6 transfer size
    ///register
    pub const fs_hctsiz6 = Register(fs_hctsiz6_val).init(0x50000400 + 0x1D0);

    //////////////////////////
    ///FS_HCTSIZ7
    const fs_hctsiz7_val = packed struct {
        ///XFRSIZ [0:18]
        ///Transfer size
        xfrsiz: u19 = 0,
        ///PKTCNT [19:28]
        ///Packet count
        pktcnt: u10 = 0,
        ///DPID [29:30]
        ///Data PID
        dpid: u2 = 0,
        _unused31: u1 = 0,
    };
    ///OTG_FS host channel-7 transfer size
    ///register
    pub const fs_hctsiz7 = Register(fs_hctsiz7_val).init(0x50000400 + 0x1F0);
};

///USB on the go full speed
pub const otg_fs_pwrclk = struct {

    //////////////////////////
    ///FS_PCGCCTL
    const fs_pcgcctl_val = packed struct {
        ///STPPCLK [0:0]
        ///Stop PHY clock
        stppclk: u1 = 0,
        ///GATEHCLK [1:1]
        ///Gate HCLK
        gatehclk: u1 = 0,
        _unused2: u2 = 0,
        ///PHYSUSP [4:4]
        ///PHY Suspended
        physusp: u1 = 0,
        _unused5: u27 = 0,
    };
    ///OTG_FS power and clock gating control
    ///register
    pub const fs_pcgcctl = Register(fs_pcgcctl_val).init(0x50000E00 + 0x0);
};

///Ethernet: MAC management counters
pub const ethernet_mmc = struct {

    //////////////////////////
    ///MMCCR
    const mmccr_val = packed struct {
        ///CR [0:0]
        ///Counter reset
        cr: u1 = 0,
        ///CSR [1:1]
        ///Counter stop rollover
        csr: u1 = 0,
        ///ROR [2:2]
        ///Reset on read
        ror: u1 = 0,
        _unused3: u28 = 0,
        ///MCF [31:31]
        ///MMC counter freeze
        mcf: u1 = 0,
    };
    ///Ethernet MMC control register
    ///(ETH_MMCCR)
    pub const mmccr = Register(mmccr_val).init(0x40028100 + 0x0);

    //////////////////////////
    ///MMCRIR
    const mmcrir_val = packed struct {
        _unused0: u5 = 0,
        ///RFCES [5:5]
        ///Received frames CRC error
        ///status
        rfces: u1 = 0,
        ///RFAES [6:6]
        ///Received frames alignment error
        ///status
        rfaes: u1 = 0,
        _unused7: u10 = 0,
        ///RGUFS [17:17]
        ///Received Good Unicast Frames
        ///Status
        rgufs: u1 = 0,
        _unused18: u14 = 0,
    };
    ///Ethernet MMC receive interrupt register
    ///(ETH_MMCRIR)
    pub const mmcrir = Register(mmcrir_val).init(0x40028100 + 0x4);

    //////////////////////////
    ///MMCTIR
    const mmctir_val = packed struct {
        _unused0: u14 = 0,
        ///TGFSCS [14:14]
        ///Transmitted good frames single collision
        ///status
        tgfscs: u1 = 0,
        ///TGFMSCS [15:15]
        ///Transmitted good frames more single
        ///collision status
        tgfmscs: u1 = 0,
        _unused16: u5 = 0,
        ///TGFS [21:21]
        ///Transmitted good frames
        ///status
        tgfs: u1 = 0,
        _unused22: u10 = 0,
    };
    ///Ethernet MMC transmit interrupt register
    ///(ETH_MMCTIR)
    pub const mmctir = Register(mmctir_val).init(0x40028100 + 0x8);

    //////////////////////////
    ///MMCRIMR
    const mmcrimr_val = packed struct {
        _unused0: u5 = 0,
        ///RFCEM [5:5]
        ///Received frame CRC error
        ///mask
        rfcem: u1 = 0,
        ///RFAEM [6:6]
        ///Received frames alignment error
        ///mask
        rfaem: u1 = 0,
        _unused7: u10 = 0,
        ///RGUFM [17:17]
        ///Received good unicast frames
        ///mask
        rgufm: u1 = 0,
        _unused18: u14 = 0,
    };
    ///Ethernet MMC receive interrupt mask register
    ///(ETH_MMCRIMR)
    pub const mmcrimr = Register(mmcrimr_val).init(0x40028100 + 0xC);

    //////////////////////////
    ///MMCTIMR
    const mmctimr_val = packed struct {
        _unused0: u14 = 0,
        ///TGFSCM [14:14]
        ///Transmitted good frames single collision
        ///mask
        tgfscm: u1 = 0,
        ///TGFMSCM [15:15]
        ///Transmitted good frames more single
        ///collision mask
        tgfmscm: u1 = 0,
        _unused16: u5 = 0,
        ///TGFM [21:21]
        ///Transmitted good frames
        ///mask
        tgfm: u1 = 0,
        _unused22: u10 = 0,
    };
    ///Ethernet MMC transmit interrupt mask
    ///register (ETH_MMCTIMR)
    pub const mmctimr = Register(mmctimr_val).init(0x40028100 + 0x10);

    //////////////////////////
    ///MMCTGFSCCR
    const mmctgfsccr_val = packed struct {
        ///TGFSCC [0:31]
        ///Transmitted good frames after a single
        ///collision counter
        tgfscc: u32 = 0,
    };
    ///Ethernet MMC transmitted good frames after a
    ///single collision counter
    pub const mmctgfsccr = RegisterRW(mmctgfsccr_val, void).init(0x40028100 + 0x4C);

    //////////////////////////
    ///MMCTGFMSCCR
    const mmctgfmsccr_val = packed struct {
        ///TGFMSCC [0:31]
        ///Transmitted good frames after more than
        ///a single collision counter
        tgfmscc: u32 = 0,
    };
    ///Ethernet MMC transmitted good frames after
    ///more than a single collision
    pub const mmctgfmsccr = RegisterRW(mmctgfmsccr_val, void).init(0x40028100 + 0x50);

    //////////////////////////
    ///MMCTGFCR
    const mmctgfcr_val = packed struct {
        ///TGFC [0:31]
        ///Transmitted good frames
        ///counter
        tgfc: u32 = 0,
    };
    ///Ethernet MMC transmitted good frames counter
    ///register
    pub const mmctgfcr = RegisterRW(mmctgfcr_val, void).init(0x40028100 + 0x68);

    //////////////////////////
    ///MMCRFCECR
    const mmcrfcecr_val = packed struct {
        ///RFCFC [0:31]
        ///Received frames with CRC error
        ///counter
        rfcfc: u32 = 0,
    };
    ///Ethernet MMC received frames with CRC error
    ///counter register
    pub const mmcrfcecr = RegisterRW(mmcrfcecr_val, void).init(0x40028100 + 0x94);

    //////////////////////////
    ///MMCRFAECR
    const mmcrfaecr_val = packed struct {
        ///RFAEC [0:31]
        ///Received frames with alignment error
        ///counter
        rfaec: u32 = 0,
    };
    ///Ethernet MMC received frames with alignment
    ///error counter register
    pub const mmcrfaecr = RegisterRW(mmcrfaecr_val, void).init(0x40028100 + 0x98);

    //////////////////////////
    ///MMCRGUFCR
    const mmcrgufcr_val = packed struct {
        ///RGUFC [0:31]
        ///Received good unicast frames
        ///counter
        rgufc: u32 = 0,
    };
    ///MMC received good unicast frames counter
    ///register
    pub const mmcrgufcr = RegisterRW(mmcrgufcr_val, void).init(0x40028100 + 0xC4);
};

///Ethernet: media access control
pub const ethernet_mac = struct {

    //////////////////////////
    ///MACCR
    const maccr_val = packed struct {
        _unused0: u2 = 0,
        ///RE [2:2]
        ///Receiver enable
        re: u1 = 0,
        ///TE [3:3]
        ///Transmitter enable
        te: u1 = 0,
        ///DC [4:4]
        ///Deferral check
        dc: u1 = 0,
        ///BL [5:6]
        ///Back-off limit
        bl: u2 = 0,
        ///APCS [7:7]
        ///Automatic pad/CRC
        ///stripping
        apcs: u1 = 0,
        _unused8: u1 = 0,
        ///RD [9:9]
        ///Retry disable
        rd: u1 = 0,
        ///IPCO [10:10]
        ///IPv4 checksum offload
        ipco: u1 = 0,
        ///DM [11:11]
        ///Duplex mode
        dm: u1 = 0,
        ///LM [12:12]
        ///Loopback mode
        lm: u1 = 0,
        ///ROD [13:13]
        ///Receive own disable
        rod: u1 = 0,
        ///FES [14:14]
        ///Fast Ethernet speed
        fes: u1 = 0,
        _unused15: u1 = 0,
        ///CSD [16:16]
        ///Carrier sense disable
        csd: u1 = 0,
        ///IFG [17:19]
        ///Interframe gap
        ifg: u3 = 0,
        _unused20: u2 = 0,
        ///JD [22:22]
        ///Jabber disable
        jd: u1 = 0,
        ///WD [23:23]
        ///Watchdog disable
        wd: u1 = 0,
        _unused24: u8 = 0,
    };
    ///Ethernet MAC configuration register
    ///(ETH_MACCR)
    pub const maccr = Register(maccr_val).init(0x40028000 + 0x0);

    //////////////////////////
    ///MACFFR
    const macffr_val = packed struct {
        ///PM [0:0]
        ///Promiscuous mode
        pm: u1 = 0,
        ///HU [1:1]
        ///Hash unicast
        hu: u1 = 0,
        ///HM [2:2]
        ///Hash multicast
        hm: u1 = 0,
        ///DAIF [3:3]
        ///Destination address inverse
        ///filtering
        daif: u1 = 0,
        ///PAM [4:4]
        ///Pass all multicast
        pam: u1 = 0,
        ///BFD [5:5]
        ///Broadcast frames disable
        bfd: u1 = 0,
        ///PCF [6:7]
        ///Pass control frames
        pcf: u2 = 0,
        ///SAIF [8:8]
        ///Source address inverse
        ///filtering
        saif: u1 = 0,
        ///SAF [9:9]
        ///Source address filter
        saf: u1 = 0,
        ///HPF [10:10]
        ///Hash or perfect filter
        hpf: u1 = 0,
        _unused11: u20 = 0,
        ///RA [31:31]
        ///Receive all
        ra: u1 = 0,
    };
    ///Ethernet MAC frame filter register
    ///(ETH_MACCFFR)
    pub const macffr = Register(macffr_val).init(0x40028000 + 0x4);

    //////////////////////////
    ///MACHTHR
    const machthr_val = packed struct {
        ///HTH [0:31]
        ///Hash table high
        hth: u32 = 0,
    };
    ///Ethernet MAC hash table high
    ///register
    pub const machthr = Register(machthr_val).init(0x40028000 + 0x8);

    //////////////////////////
    ///MACHTLR
    const machtlr_val = packed struct {
        ///HTL [0:31]
        ///Hash table low
        htl: u32 = 0,
    };
    ///Ethernet MAC hash table low
    ///register
    pub const machtlr = Register(machtlr_val).init(0x40028000 + 0xC);

    //////////////////////////
    ///MACMIIAR
    const macmiiar_val = packed struct {
        ///MB [0:0]
        ///MII busy
        mb: u1 = 0,
        ///MW [1:1]
        ///MII write
        mw: u1 = 0,
        ///CR [2:4]
        ///Clock range
        cr: u3 = 0,
        _unused5: u1 = 0,
        ///MR [6:10]
        ///MII register
        mr: u5 = 0,
        ///PA [11:15]
        ///PHY address
        pa: u5 = 0,
        _unused16: u16 = 0,
    };
    ///Ethernet MAC MII address register
    ///(ETH_MACMIIAR)
    pub const macmiiar = Register(macmiiar_val).init(0x40028000 + 0x10);

    //////////////////////////
    ///MACMIIDR
    const macmiidr_val = packed struct {
        ///MD [0:15]
        ///MII data
        md: u16 = 0,
        _unused16: u16 = 0,
    };
    ///Ethernet MAC MII data register
    ///(ETH_MACMIIDR)
    pub const macmiidr = Register(macmiidr_val).init(0x40028000 + 0x14);

    //////////////////////////
    ///MACFCR
    const macfcr_val = packed struct {
        ///FCB_BPA [0:0]
        ///Flow control busy/back pressure
        ///activate
        fcb_bpa: u1 = 0,
        ///TFCE [1:1]
        ///Transmit flow control
        ///enable
        tfce: u1 = 0,
        ///RFCE [2:2]
        ///Receive flow control
        ///enable
        rfce: u1 = 0,
        ///UPFD [3:3]
        ///Unicast pause frame detect
        upfd: u1 = 0,
        ///PLT [4:5]
        ///Pause low threshold
        plt: u2 = 0,
        _unused6: u1 = 0,
        ///ZQPD [7:7]
        ///Zero-quanta pause disable
        zqpd: u1 = 0,
        _unused8: u8 = 0,
        ///PT [16:31]
        ///Pass control frames
        pt: u16 = 0,
    };
    ///Ethernet MAC flow control register
    ///(ETH_MACFCR)
    pub const macfcr = Register(macfcr_val).init(0x40028000 + 0x18);

    //////////////////////////
    ///MACVLANTR
    const macvlantr_val = packed struct {
        ///VLANTI [0:15]
        ///VLAN tag identifier (for receive
        ///frames)
        vlanti: u16 = 0,
        ///VLANTC [16:16]
        ///12-bit VLAN tag comparison
        vlantc: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Ethernet MAC VLAN tag register
    ///(ETH_MACVLANTR)
    pub const macvlantr = Register(macvlantr_val).init(0x40028000 + 0x1C);

    //////////////////////////
    ///MACRWUFFR
    const macrwuffr_val = packed struct {
        _unused0: u32 = 0,
    };
    ///Ethernet MAC remote wakeup frame filter
    ///register (ETH_MACRWUFFR)
    pub const macrwuffr = Register(macrwuffr_val).init(0x40028000 + 0x28);

    //////////////////////////
    ///MACPMTCSR
    const macpmtcsr_val = packed struct {
        ///PD [0:0]
        ///Power down
        pd: u1 = 0,
        ///MPE [1:1]
        ///Magic Packet enable
        mpe: u1 = 0,
        ///WFE [2:2]
        ///Wakeup frame enable
        wfe: u1 = 0,
        _unused3: u2 = 0,
        ///MPR [5:5]
        ///Magic packet received
        mpr: u1 = 0,
        ///WFR [6:6]
        ///Wakeup frame received
        wfr: u1 = 0,
        _unused7: u2 = 0,
        ///GU [9:9]
        ///Global unicast
        gu: u1 = 0,
        _unused10: u21 = 0,
        ///WFFRPR [31:31]
        ///Wakeup frame filter register pointer
        ///reset
        wffrpr: u1 = 0,
    };
    ///Ethernet MAC PMT control and status register
    ///(ETH_MACPMTCSR)
    pub const macpmtcsr = Register(macpmtcsr_val).init(0x40028000 + 0x2C);

    //////////////////////////
    ///MACSR
    const macsr_val = packed struct {
        _unused0: u3 = 0,
        ///PMTS [3:3]
        ///PMT status
        pmts: u1 = 0,
        ///MMCS [4:4]
        ///MMC status
        mmcs: u1 = 0,
        ///MMCRS [5:5]
        ///MMC receive status
        mmcrs: u1 = 0,
        ///MMCTS [6:6]
        ///MMC transmit status
        mmcts: u1 = 0,
        _unused7: u2 = 0,
        ///TSTS [9:9]
        ///Time stamp trigger status
        tsts: u1 = 0,
        _unused10: u22 = 0,
    };
    ///Ethernet MAC interrupt status register
    ///(ETH_MACSR)
    pub const macsr = Register(macsr_val).init(0x40028000 + 0x38);

    //////////////////////////
    ///MACIMR
    const macimr_val = packed struct {
        _unused0: u3 = 0,
        ///PMTIM [3:3]
        ///PMT interrupt mask
        pmtim: u1 = 0,
        _unused4: u5 = 0,
        ///TSTIM [9:9]
        ///Time stamp trigger interrupt
        ///mask
        tstim: u1 = 0,
        _unused10: u22 = 0,
    };
    ///Ethernet MAC interrupt mask register
    ///(ETH_MACIMR)
    pub const macimr = Register(macimr_val).init(0x40028000 + 0x3C);

    //////////////////////////
    ///MACA0HR
    const maca0hr_val = packed struct {
        ///MACA0H [0:15]
        ///MAC address0 high
        maca0h: u16 = 65535,
        _unused16: u15 = 0,
        ///MO [31:31]
        ///Always 1
        mo: u1 = 0,
    };
    ///Ethernet MAC address 0 high register
    ///(ETH_MACA0HR)
    pub const maca0hr = Register(maca0hr_val).init(0x40028000 + 0x40);

    //////////////////////////
    ///MACA0LR
    const maca0lr_val = packed struct {
        ///MACA0L [0:31]
        ///MAC address0 low
        maca0l: u32 = 4294967295,
    };
    ///Ethernet MAC address 0 low
    ///register
    pub const maca0lr = Register(maca0lr_val).init(0x40028000 + 0x44);

    //////////////////////////
    ///MACA1HR
    const maca1hr_val = packed struct {
        ///MACA1H [0:15]
        ///MAC address1 high
        maca1h: u16 = 65535,
        _unused16: u8 = 0,
        ///MBC [24:29]
        ///Mask byte control
        mbc: u6 = 0,
        ///SA [30:30]
        ///Source address
        sa: u1 = 0,
        ///AE [31:31]
        ///Address enable
        ae: u1 = 0,
    };
    ///Ethernet MAC address 1 high register
    ///(ETH_MACA1HR)
    pub const maca1hr = Register(maca1hr_val).init(0x40028000 + 0x48);

    //////////////////////////
    ///MACA1LR
    const maca1lr_val = packed struct {
        ///MACA1L [0:31]
        ///MAC address1 low
        maca1l: u32 = 4294967295,
    };
    ///Ethernet MAC address1 low
    ///register
    pub const maca1lr = Register(maca1lr_val).init(0x40028000 + 0x4C);

    //////////////////////////
    ///MACA2HR
    const maca2hr_val = packed struct {
        ///ETH_MACA2HR [0:15]
        ///Ethernet MAC address 2 high
        ///register
        eth_maca2hr: u16 = 80,
        _unused16: u8 = 0,
        ///MBC [24:29]
        ///Mask byte control
        mbc: u6 = 0,
        ///SA [30:30]
        ///Source address
        sa: u1 = 0,
        ///AE [31:31]
        ///Address enable
        ae: u1 = 0,
    };
    ///Ethernet MAC address 2 high register
    ///(ETH_MACA2HR)
    pub const maca2hr = Register(maca2hr_val).init(0x40028000 + 0x50);

    //////////////////////////
    ///MACA2LR
    const maca2lr_val = packed struct {
        ///MACA2L [0:30]
        ///MAC address2 low
        maca2l: u31 = 2147483647,
        _unused31: u1 = 0,
    };
    ///Ethernet MAC address 2 low
    ///register
    pub const maca2lr = Register(maca2lr_val).init(0x40028000 + 0x54);

    //////////////////////////
    ///MACA3HR
    const maca3hr_val = packed struct {
        ///MACA3H [0:15]
        ///MAC address3 high
        maca3h: u16 = 65535,
        _unused16: u8 = 0,
        ///MBC [24:29]
        ///Mask byte control
        mbc: u6 = 0,
        ///SA [30:30]
        ///Source address
        sa: u1 = 0,
        ///AE [31:31]
        ///Address enable
        ae: u1 = 0,
    };
    ///Ethernet MAC address 3 high register
    ///(ETH_MACA3HR)
    pub const maca3hr = Register(maca3hr_val).init(0x40028000 + 0x58);

    //////////////////////////
    ///MACA3LR
    const maca3lr_val = packed struct {
        ///MBCA3L [0:31]
        ///MAC address3 low
        mbca3l: u32 = 4294967295,
    };
    ///Ethernet MAC address 3 low
    ///register
    pub const maca3lr = Register(maca3lr_val).init(0x40028000 + 0x5C);
};

///Ethernet: Precision time protocol
pub const ethernet_ptp = struct {

    //////////////////////////
    ///PTPTSCR
    const ptptscr_val = packed struct {
        ///TSE [0:0]
        ///Time stamp enable
        tse: u1 = 0,
        ///TSFCU [1:1]
        ///Time stamp fine or coarse
        ///update
        tsfcu: u1 = 0,
        ///TSSTI [2:2]
        ///Time stamp system time
        ///initialize
        tssti: u1 = 0,
        ///TSSTU [3:3]
        ///Time stamp system time
        ///update
        tsstu: u1 = 0,
        ///TSITE [4:4]
        ///Time stamp interrupt trigger
        ///enable
        tsite: u1 = 0,
        ///TSARU [5:5]
        ///Time stamp addend register
        ///update
        tsaru: u1 = 0,
        _unused6: u26 = 0,
    };
    ///Ethernet PTP time stamp control register
    ///(ETH_PTPTSCR)
    pub const ptptscr = Register(ptptscr_val).init(0x40028700 + 0x0);

    //////////////////////////
    ///PTPSSIR
    const ptpssir_val = packed struct {
        ///STSSI [0:7]
        ///System time subsecond
        ///increment
        stssi: u8 = 0,
        _unused8: u24 = 0,
    };
    ///Ethernet PTP subsecond increment
    ///register
    pub const ptpssir = Register(ptpssir_val).init(0x40028700 + 0x4);

    //////////////////////////
    ///PTPTSHR
    const ptptshr_val = packed struct {
        ///STS [0:31]
        ///System time second
        sts: u32 = 0,
    };
    ///Ethernet PTP time stamp high
    ///register
    pub const ptptshr = RegisterRW(ptptshr_val, void).init(0x40028700 + 0x8);

    //////////////////////////
    ///PTPTSLR
    const ptptslr_val = packed struct {
        ///STSS [0:30]
        ///System time subseconds
        stss: u31 = 0,
        ///STPNS [31:31]
        ///System time positive or negative
        ///sign
        stpns: u1 = 0,
    };
    ///Ethernet PTP time stamp low register
    ///(ETH_PTPTSLR)
    pub const ptptslr = RegisterRW(ptptslr_val, void).init(0x40028700 + 0xC);

    //////////////////////////
    ///PTPTSHUR
    const ptptshur_val = packed struct {
        ///TSUS [0:31]
        ///Time stamp update second
        tsus: u32 = 0,
    };
    ///Ethernet PTP time stamp high update
    ///register
    pub const ptptshur = Register(ptptshur_val).init(0x40028700 + 0x10);

    //////////////////////////
    ///PTPTSLUR
    const ptptslur_val = packed struct {
        ///TSUSS [0:30]
        ///Time stamp update
        ///subseconds
        tsuss: u31 = 0,
        ///TSUPNS [31:31]
        ///Time stamp update positive or negative
        ///sign
        tsupns: u1 = 0,
    };
    ///Ethernet PTP time stamp low update register
    ///(ETH_PTPTSLUR)
    pub const ptptslur = Register(ptptslur_val).init(0x40028700 + 0x14);

    //////////////////////////
    ///PTPTSAR
    const ptptsar_val = packed struct {
        ///TSA [0:31]
        ///Time stamp addend
        tsa: u32 = 0,
    };
    ///Ethernet PTP time stamp addend
    ///register
    pub const ptptsar = Register(ptptsar_val).init(0x40028700 + 0x18);

    //////////////////////////
    ///PTPTTHR
    const ptptthr_val = packed struct {
        ///TTSH [0:31]
        ///Target time stamp high
        ttsh: u32 = 0,
    };
    ///Ethernet PTP target time high
    ///register
    pub const ptptthr = Register(ptptthr_val).init(0x40028700 + 0x1C);

    //////////////////////////
    ///PTPTTLR
    const ptpttlr_val = packed struct {
        ///TTSL [0:31]
        ///Target time stamp low
        ttsl: u32 = 0,
    };
    ///Ethernet PTP target time low
    ///register
    pub const ptpttlr = Register(ptpttlr_val).init(0x40028700 + 0x20);
};

///Ethernet: DMA controller operation
pub const ethernet_dma = struct {

    //////////////////////////
    ///DMABMR
    const dmabmr_val = packed struct {
        ///SR [0:0]
        ///Software reset
        sr: u1 = 1,
        ///DA [1:1]
        ///DMA Arbitration
        da: u1 = 0,
        ///DSL [2:6]
        ///Descriptor skip length
        dsl: u5 = 0,
        _unused7: u1 = 0,
        ///PBL [8:13]
        ///Programmable burst length
        pbl: u6 = 1,
        ///RTPR [14:15]
        ///Rx Tx priority ratio
        rtpr: u2 = 0,
        ///FB [16:16]
        ///Fixed burst
        fb: u1 = 0,
        ///RDP [17:22]
        ///Rx DMA PBL
        rdp: u6 = 1,
        ///USP [23:23]
        ///Use separate PBL
        usp: u1 = 0,
        ///FPM [24:24]
        ///4xPBL mode
        fpm: u1 = 0,
        ///AAB [25:25]
        ///Address-aligned beats
        aab: u1 = 0,
        _unused26: u6 = 0,
    };
    ///Ethernet DMA bus mode register
    pub const dmabmr = Register(dmabmr_val).init(0x40029000 + 0x0);

    //////////////////////////
    ///DMATPDR
    const dmatpdr_val = packed struct {
        ///TPD [0:31]
        ///Transmit poll demand
        tpd: u32 = 0,
    };
    ///Ethernet DMA transmit poll demand
    ///register
    pub const dmatpdr = Register(dmatpdr_val).init(0x40029000 + 0x4);

    //////////////////////////
    ///DMARPDR
    const dmarpdr_val = packed struct {
        ///RPD [0:31]
        ///Receive poll demand
        rpd: u32 = 0,
    };
    ///EHERNET DMA receive poll demand
    ///register
    pub const dmarpdr = Register(dmarpdr_val).init(0x40029000 + 0x8);

    //////////////////////////
    ///DMARDLAR
    const dmardlar_val = packed struct {
        ///SRL [0:31]
        ///Start of receive list
        srl: u32 = 0,
    };
    ///Ethernet DMA receive descriptor list address
    ///register
    pub const dmardlar = Register(dmardlar_val).init(0x40029000 + 0xC);

    //////////////////////////
    ///DMATDLAR
    const dmatdlar_val = packed struct {
        ///STL [0:31]
        ///Start of transmit list
        stl: u32 = 0,
    };
    ///Ethernet DMA transmit descriptor list
    ///address register
    pub const dmatdlar = Register(dmatdlar_val).init(0x40029000 + 0x10);

    //////////////////////////
    ///DMASR
    const dmasr_val = packed struct {
        ///TS [0:0]
        ///Transmit status
        ts: u1 = 0,
        ///TPSS [1:1]
        ///Transmit process stopped
        ///status
        tpss: u1 = 0,
        ///TBUS [2:2]
        ///Transmit buffer unavailable
        ///status
        tbus: u1 = 0,
        ///TJTS [3:3]
        ///Transmit jabber timeout
        ///status
        tjts: u1 = 0,
        ///ROS [4:4]
        ///Receive overflow status
        ros: u1 = 0,
        ///TUS [5:5]
        ///Transmit underflow status
        tus: u1 = 0,
        ///RS [6:6]
        ///Receive status
        rs: u1 = 0,
        ///RBUS [7:7]
        ///Receive buffer unavailable
        ///status
        rbus: u1 = 0,
        ///RPSS [8:8]
        ///Receive process stopped
        ///status
        rpss: u1 = 0,
        ///PWTS [9:9]
        ///Receive watchdog timeout
        ///status
        pwts: u1 = 0,
        ///ETS [10:10]
        ///Early transmit status
        ets: u1 = 0,
        _unused11: u2 = 0,
        ///FBES [13:13]
        ///Fatal bus error status
        fbes: u1 = 0,
        ///ERS [14:14]
        ///Early receive status
        ers: u1 = 0,
        ///AIS [15:15]
        ///Abnormal interrupt summary
        ais: u1 = 0,
        ///NIS [16:16]
        ///Normal interrupt summary
        nis: u1 = 0,
        ///RPS [17:19]
        ///Receive process state
        rps: u3 = 0,
        ///TPS [20:22]
        ///Transmit process state
        tps: u3 = 0,
        ///EBS [23:25]
        ///Error bits status
        ebs: u3 = 0,
        _unused26: u1 = 0,
        ///MMCS [27:27]
        ///MMC status
        mmcs: u1 = 0,
        ///PMTS [28:28]
        ///PMT status
        pmts: u1 = 0,
        ///TSTS [29:29]
        ///Time stamp trigger status
        tsts: u1 = 0,
        _unused30: u2 = 0,
    };
    ///Ethernet DMA status register
    pub const dmasr = Register(dmasr_val).init(0x40029000 + 0x14);

    //////////////////////////
    ///DMAOMR
    const dmaomr_val = packed struct {
        _unused0: u1 = 0,
        ///SR [1:1]
        ///SR
        sr: u1 = 0,
        ///OSF [2:2]
        ///OSF
        osf: u1 = 0,
        ///RTC [3:4]
        ///RTC
        rtc: u2 = 0,
        _unused5: u1 = 0,
        ///FUGF [6:6]
        ///FUGF
        fugf: u1 = 0,
        ///FEF [7:7]
        ///FEF
        fef: u1 = 0,
        _unused8: u5 = 0,
        ///ST [13:13]
        ///ST
        st: u1 = 0,
        ///TTC [14:16]
        ///TTC
        ttc: u3 = 0,
        _unused17: u3 = 0,
        ///FTF [20:20]
        ///FTF
        ftf: u1 = 0,
        ///TSF [21:21]
        ///TSF
        tsf: u1 = 0,
        _unused22: u2 = 0,
        ///DFRF [24:24]
        ///DFRF
        dfrf: u1 = 0,
        ///RSF [25:25]
        ///RSF
        rsf: u1 = 0,
        ///DTCEFD [26:26]
        ///DTCEFD
        dtcefd: u1 = 0,
        _unused27: u5 = 0,
    };
    ///Ethernet DMA operation mode
    ///register
    pub const dmaomr = Register(dmaomr_val).init(0x40029000 + 0x18);

    //////////////////////////
    ///DMAIER
    const dmaier_val = packed struct {
        ///TIE [0:0]
        ///Transmit interrupt enable
        tie: u1 = 0,
        ///TPSIE [1:1]
        ///Transmit process stopped interrupt
        ///enable
        tpsie: u1 = 0,
        ///TBUIE [2:2]
        ///Transmit buffer unavailable interrupt
        ///enable
        tbuie: u1 = 0,
        ///TJTIE [3:3]
        ///Transmit jabber timeout interrupt
        ///enable
        tjtie: u1 = 0,
        ///ROIE [4:4]
        ///Overflow interrupt enable
        roie: u1 = 0,
        ///TUIE [5:5]
        ///Underflow interrupt enable
        tuie: u1 = 0,
        ///RIE [6:6]
        ///Receive interrupt enable
        rie: u1 = 0,
        ///RBUIE [7:7]
        ///Receive buffer unavailable interrupt
        ///enable
        rbuie: u1 = 0,
        ///RPSIE [8:8]
        ///Receive process stopped interrupt
        ///enable
        rpsie: u1 = 0,
        ///RWTIE [9:9]
        ///receive watchdog timeout interrupt
        ///enable
        rwtie: u1 = 0,
        ///ETIE [10:10]
        ///Early transmit interrupt
        ///enable
        etie: u1 = 0,
        _unused11: u2 = 0,
        ///FBEIE [13:13]
        ///Fatal bus error interrupt
        ///enable
        fbeie: u1 = 0,
        ///ERIE [14:14]
        ///Early receive interrupt
        ///enable
        erie: u1 = 0,
        ///AISE [15:15]
        ///Abnormal interrupt summary
        ///enable
        aise: u1 = 0,
        ///NISE [16:16]
        ///Normal interrupt summary
        ///enable
        nise: u1 = 0,
        _unused17: u15 = 0,
    };
    ///Ethernet DMA interrupt enable
    ///register
    pub const dmaier = Register(dmaier_val).init(0x40029000 + 0x1C);

    //////////////////////////
    ///DMAMFBOCR
    const dmamfbocr_val = packed struct {
        ///MFC [0:15]
        ///Missed frames by the
        ///controller
        mfc: u16 = 0,
        ///OMFC [16:16]
        ///Overflow bit for missed frame
        ///counter
        omfc: u1 = 0,
        ///MFA [17:27]
        ///Missed frames by the
        ///application
        mfa: u11 = 0,
        ///OFOC [28:28]
        ///Overflow bit for FIFO overflow
        ///counter
        ofoc: u1 = 0,
        _unused29: u3 = 0,
    };
    ///Ethernet DMA missed frame and buffer
    ///overflow counter register
    pub const dmamfbocr = RegisterRW(dmamfbocr_val, void).init(0x40029000 + 0x20);

    //////////////////////////
    ///DMACHTDR
    const dmachtdr_val = packed struct {
        ///HTDAP [0:31]
        ///Host transmit descriptor address
        ///pointer
        htdap: u32 = 0,
    };
    ///Ethernet DMA current host transmit
    ///descriptor register
    pub const dmachtdr = RegisterRW(dmachtdr_val, void).init(0x40029000 + 0x48);

    //////////////////////////
    ///DMACHRDR
    const dmachrdr_val = packed struct {
        ///HRDAP [0:31]
        ///Host receive descriptor address
        ///pointer
        hrdap: u32 = 0,
    };
    ///Ethernet DMA current host receive descriptor
    ///register
    pub const dmachrdr = RegisterRW(dmachrdr_val, void).init(0x40029000 + 0x4C);

    //////////////////////////
    ///DMACHTBAR
    const dmachtbar_val = packed struct {
        ///HTBAP [0:31]
        ///Host transmit buffer address
        ///pointer
        htbap: u32 = 0,
    };
    ///Ethernet DMA current host transmit buffer
    ///address register
    pub const dmachtbar = RegisterRW(dmachtbar_val, void).init(0x40029000 + 0x50);

    //////////////////////////
    ///DMACHRBAR
    const dmachrbar_val = packed struct {
        ///HRBAP [0:31]
        ///Host receive buffer address
        ///pointer
        hrbap: u32 = 0,
    };
    ///Ethernet DMA current host receive buffer
    ///address register
    pub const dmachrbar = RegisterRW(dmachrbar_val, void).init(0x40029000 + 0x54);
};
