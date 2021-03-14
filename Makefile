# Disable built-in rules and variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables

BUILD_FLAGS = -O ReleaseSmall -target thumb-freestanding -mcpu cortex_m3
LINKER_SCRIPT = arm_cm3.ld
LD_FLAGS = --gc-sections -nostdlib
OBJS = startup.o main.o
PROG = firmware

%.o: %.zig
	zig build-obj ${BUILD_FLAGS} $<

${PROG}: ${OBJS}
	zig build-exe ${BUILD_FLAGS} $(OBJS:%=%) --name $@.elf --script ${LINKER_SCRIPT}
#	arm-none-eabi-ld ${OBJS} -o $@.elf -T ${LINKER_SCRIPT} -Map $@.map ${LD_FLAGS}

clean:
	rm -rf ${PROG}.* ${OBJS} $(OBJS:%.o=%.h) zig-cache

.PHONY: clean
