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

clean:
	$(RM) $(TARGET)*  *.obj *.pdb *.exe
