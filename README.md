# RGBLaunch

 CLI/WB launcher stub for PiStorm / Emu68 VideoCore with FrameThrower or HDMI autoswitch
 
 Opens a native chipset screen to force the RGB mode switch,
 waits a moment for the display to settle, then launches
 the target app/demo/game. Cleans up on exit.

 Usage:  RGBLaunch [SCREENMODE <modeid>] [DEPTH <n>] [DELAY <ticks>] [ASYNC] <command> [args...]

   SCREENMODE  Hex mode ID (default: $0 = PAL LORES 320x256)
   
   Common values:               
   $21000  PAL  HIRES  640x256                 
   $20000  PAL  LORES  320x256
                 
   DEPTH       Bitplanes, 1-8 (default: 2)
   DELAY       Ticks to wait after screen open before launch (default: 10, ~0.5s)
   ASYNC       Close the screen after any delay (default: leave open until app finishes)
   <command>   The program to run, with any arguments
   

Use RGBLaunch ? to show this help.
