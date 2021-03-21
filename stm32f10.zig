usingnamespace @import("core_cm3.zig");
const mcu = @import("stm32f103.zig");

const FLASH_BASE: u32 = 0x08000000;
const VECT_TAB_OFFSET = 0x0;
const HSE_STARTUP_TIMEOUT: u16 = 0x0500;


// copied verbatim from STM32 SDK
pub fn SystemInit() void {
    //* Reset the RCC clock configuration to the default reset state(for debug purpose) */
    //* Set HSION bit */
    mcu.rcc.cr.write_bit("hsion", 1);

    //* Reset SW, HPRE, PPRE1, PPRE2, ADCPRE and MCO bits */
    mcu.rcc.cfgr.modify_mask(.{
        .sw = 0,
        .hpre = 0,
        .ppre1 = 0,
        .ppre2 = 0,
        .adcpre = 0,
        .mco = 0,
    });

    //* Reset HSEON, CSSON and PLLON bits */
    mcu.rcc.cr.modify_mask(.{
        .hseon = 0,
        .csson = 0,
        .pllon = 0,
    });

    //* Reset HSEBYP bit */
    mcu.rcc.cr.modify_mask(.{
        .hsebyp = 0,
    });

    //* Reset PLLSRC, PLLXTPRE, PLLMUL and USBPRE/OTGFSPRE bits */
    mcu.rcc.cfgr.modify_mask(.{
        .pllsrc = 0,
        .pllmul = 0,
        .otgfspre = 0,
    });

    //* Disable all interrupts and clear pending bits  */
    mcu.rcc.cir.write(.{
        .cssc = 1,
        .pllrdyc = 1,
        .hserdyc = 1,
        .hsirdyc = 1,
        .lserdyc = 1,
        .lsirdyc = 1,
    });

    //* Configure the System clock frequency, HCLK, PCLK2 and PCLK1 prescalers */
    //* Configure the Flash Latency cycles and enable prefetch buffer */
    SetSysClock();

    SCB.*.VTOR = FLASH_BASE | VECT_TAB_OFFSET; //* Vector Table Relocation in Internal FLASH. */
}

fn SetSysClock() void {
    var StartUpCounter: u32 = 0;
    var HSEStatus: u32 = 0;

    //* SYSCLK, HCLK, PCLK2 and PCLK1 configuration ---------------------------*/
    //* Enable HSE */
    mcu.rcc.cr.write_bit("hseon", 1);

    //* Wait till HSE is ready and if Time out is reached exit */
    StartUpCounter += 1;
    while ((mcu.rcc.cr.read_bit("hserdy") == 0) and (StartUpCounter != HSE_STARTUP_TIMEOUT)) {
        StartUpCounter += 1;
    }

    if (mcu.rcc.cr.read_bit("hserdy") != 0) {
        HSEStatus = 0x01;
    } else {
        HSEStatus = 0x00;
    }

    if (HSEStatus == 0x01) {
        mcu.flash.acr.modify_mask(.{
            //* Enable Prefetch Buffer */
            .prftbe = 1,
            //* Flash 2 wait state */
            .latency = 0b010,
        });

        mcu.rcc.cfgr.modify_mask(.{
            // HCLK = SYSCLK
            .hpre = 0,
            // PCLK2 = HCLK
            .ppre2 = 0,
            // PCLK1 = HCLK/2
            .ppre1 = 0b100, // HCLK divided by 2
            .pllsrc = 0,
            .pllxtpre = 0,
            .pllmul = 0b111, // x 9
        });

        //* Enable PLL */
        mcu.rcc.cr.write_bit("pllon", 1);
        while (mcu.rcc.cr.read_bit("pllon") == 0) {}

        //* Select PLL as system clock source */
        mcu.rcc.cfgr.modify_mask(.{
            .sw = 0b10,
        });

        //* Wait till PLL is used as system clock source */
        while (mcu.rcc.cfgr.read().sws != 0b10) {}
    } else { //* If HSE fails to start-up, the application will have wrong clock
        //  configuration. User can add here some code to deal with this error */
    }
}
