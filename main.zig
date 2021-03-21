usingnamespace @import("stm32f10.zig");
const mcu = @import("stm32f103.zig");

export fn main() void {
    SystemInit();
    mcu.rcc.apb2enr.modify(.{ .iopcen = 1 });

    mcu.gpioc.crh.modify_mask(.{
        .cnf13 = 0b00,
        .mode13 = 0b10,
    });

    var x: u1 = mcu.gpioc.odr.read_bit("odr13");
    while (true) {
        mcu.gpioc.odr.write_bit("odr13", x);
        x = ~x;
        var i: u32 = 0;
        while (i < 1000000) {
            asm volatile ("nop");
            i += 1;
        }
    }
}
