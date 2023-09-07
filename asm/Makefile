deb:
	nasm -g -F dwarf -f elf64 -o render.o render.asm && ld -g -o render render.o

rel:
	nasm -f elf64 -o render.o render.asm && ld -o render render.o --strip-all

perf:
	nasm -f elf64 -o render.o render.asm && strip --discard-all render.o && \
            ld -o render render.o
