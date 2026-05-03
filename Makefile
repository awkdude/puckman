ODIN_TARGET = odin_gl
RM := rm
ifeq ($(OS),Windows_NT)
	SHELL := cmd.exe
	RM := del
endif

.PHONY: build clean

build:
	odin build . -debug --collection:odinlib=../odinlib

build_sdl:
	odin build . -debug --collection:odinlib=../odinlib --define:BACKEND=sdl

clean:
	$(RM) $(TARGET)* 
