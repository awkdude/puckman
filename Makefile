TARGET = puckman
RM := rm
ifeq ($(OS),Windows_NT)
	SHELL := cmd.exe
	RM := del
endif

.PHONY: build clean

build:
	odin build . -debug -sanitize:address --collection:odinlib=../odinlib

build_sdl:
	odin build . -debug -sanitize:address --collection:odinlib=../odinlib --define:BACKEND=sdl

build_release:
	odin build . -o:speed --collection:odinlib=../odinlib

clean:
	$(RM) $(TARGET)*  *.obj *.pdb *.exe
