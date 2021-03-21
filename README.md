Possible compiler bug?

the `.modify()` "does not work" while `.modify_mask()` does

```
$ arm-none-eabi-gdb -batch -ex 'file firmware.elf' -ex 'disassemble use_modify'
Dump of assembler code for function use_modify:
   0x08000084 <+0>:     sub     sp, #8
   0x08000086 <+2>:     ldr     r0, [pc, #48]   ; (0x80000b8 <use_modify+52>)
   0x08000088 <+4>:     movs    r3, #2
   0x0800008a <+6>:     ldr     r1, [r0, #0]
   0x0800008c <+8>:     strh.w  r1, [sp, #4]
   0x08000090 <+12>:    ldrh.w  r2, [sp, #4]
   0x08000094 <+16>:    strh    r2, [r0, #0]
   0x08000096 <+18>:    lsrs    r2, r1, #16
   0x08000098 <+20>:    lsrs    r1, r1, #24
   0x0800009a <+22>:    bfi     r2, r3, #4, #28
   0x0800009e <+26>:    strb.w  r1, [sp, #2]
   0x080000a2 <+30>:    strb.w  r2, [sp, #3]
   0x080000a6 <+34>:    ldrb.w  r1, [sp, #3]
   0x080000aa <+38>:    strb    r1, [r0, #2]
   0x080000ac <+40>:    ldrb.w  r1, [sp, #2]
   0x080000b0 <+44>:    strb    r1, [r0, #3]
   0x080000b2 <+46>:    add     sp, #8
   0x080000b4 <+48>:    bx      lr
   0x080000b6 <+50>:    nop
   0x080000b8 <+52>:    asrs    r4, r0, #32
   0x080000ba <+54>:    ands    r1, r0
End of assembler dump.
```

```
$ arm-none-eabi-gdb -batch -ex 'file firmware.elf' -ex 'disassemble use_modify_mask' 
Dump of assembler code for function use_modify_mask:
   0x080000bc <+0>:     ldr     r0, [pc, #8]    ; (0x80000c8 <use_modify_mask+12>)
   0x080000be <+2>:     ldr     r1, [r0, #0]
   0x080000c0 <+4>:     orr.w   r1, r1, #2097152        ; 0x200000
   0x080000c4 <+8>:     str     r1, [r0, #0]
   0x080000c6 <+10>:    bx      lr
   0x080000c8 <+12>:    asrs    r4, r0, #32
   0x080000ca <+14>:    ands    r1, r0
End of assembler dump.
```