const builtin = @import("builtin");

extern fn main() void;

extern const _sidata: u32;
extern const _sdata: u32;
extern const _edata: u32;
extern const _sbss: u32;
extern const _ebss: u32;

export fn Reset_Handler() void {
    // copy data from flash to RAM

    var data_read_ptr = _sidata;
    var data_write_ptr = _sdata;

    while (data_write_ptr != _edata) {
        @intToPtr(*u32, data_write_ptr).* = @intToPtr(*u32, data_read_ptr).*;
        data_read_ptr += 4;
        data_write_ptr += 4;

    }

    var bss_write_ptr = _sbss;

    while (bss_write_ptr != _ebss) {
        @intToPtr(*u32, bss_write_ptr).* = 0;
    }

    // start
    main();
}

export fn BusyDummy_Handler() void {
    while (true) {}
}

export fn Dummy_Handler() void {}

extern fn NMI_Handler() void;
extern fn HardFault_Handler() void;
extern fn MemManage_Handler() void;
extern fn BusFault_Handler() void;
extern fn UsageFault_Handler() void;
extern fn SVC_Handler() void;
extern fn DebugMon_Handler() void;
extern fn PendSV_Handler() void;
extern fn SysTick_Handler() void;

const Isr = fn () callconv(.C) void;

export var vector_table linksection(".isr_vector") = [_]?Isr{
    Reset_Handler,
    NMI_Handler,
    HardFault_Handler,
    MemManage_Handler,
    BusFault_Handler,
    UsageFault_Handler,
    null,
    null,
    null,
    null,
    SVC_Handler,
    DebugMon_Handler,
    null,
    PendSV_Handler,
    SysTick_Handler,
};
