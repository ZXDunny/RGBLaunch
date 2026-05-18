/* RGBLaunch.e
**
** CLI launcher stub for PiStorm / Emu68 VideoCore with FrameThrower or HDMI autoswitch
** Opens a native chipset screen to force the RGB mode switch,
** waits a moment for the FrameThrower to settle, then launches
** the target app/demo/game. Cleans up on exit.
**
** Usage:  RGBLaunch [SCREENMODE <modeid>] [DEPTH <n>] [DELAY <ticks>] [ASYNC] <command> [args...]
**
**   SCREENMODE  Hex mode ID (default: $0 = PAL LORES 320x256)
**               Common values:
**                 $21000  PAL  HIRES  640x256
**                 $20000  PAL  LORES  320x256
**   DEPTH       Bitplanes, 1-8 (default: 1)
**   DELAY       Ticks to wait after screen open before launch (default: 10, ~0.5s)
**   ASYNC       Close the screen after any delay (default: leave open until app finishes)
**   <command>   The program to run, with any arguments
**
** Compile with: ec RGBLaunch.e
**
*/

MODULE 'intuition/screens',
       'intuition/intuition',
       'graphics/gfxbase',
       'graphics/modeid',
       'dos/dos',
       'dos/dosextens',
       'dos/dostags',
       'utility/tagitem',
       'libraries/asl',
       'asl'

CONST DEF_MODEID = LORES_KEY /* PAL LORES 320x256 */
CONST DEF_DEPTH  = 2
CONST DEF_DELAY  = 10        /* ticks (~0.5s at 50Hz PAL) */

/* ------------------------------------------------------------------ */
/* Case-insensitive ASCII uppercase                                    */
/* ------------------------------------------------------------------ */
PROC upper(c)
  IF (c >= "a") AND (c <= "z") THEN RETURN c-32
  RETURN c
ENDPROC

/* ------------------------------------------------------------------ */
/* Case-insensitive string compare                                     */
/* ------------------------------------------------------------------ */
PROC strieq(a:PTR TO CHAR, b:PTR TO CHAR)
  DEF ca, cb
  ca := a[]
  cb := b[]
  WHILE (ca <> 0) AND (cb <> 0)
    IF upper(ca) <> upper(cb) THEN RETURN FALSE
    a++
    b++
    ca := a[]
    cb := b[]
  ENDWHILE
  IF (ca = 0) AND (cb = 0) THEN RETURN TRUE
  RETURN FALSE
ENDPROC

/* ------------------------------------------------------------------ */
/* Parse hex string e.g. "$20000" -> LONG                             */
/* ------------------------------------------------------------------ */
PROC hexval(s:PTR TO CHAR)
  DEF val = 0, c
  IF s[] = "$" THEN s++
  WHILE s[] <> 0
    c := s[]
    IF    (c >= "0") AND (c <= "9") 
      val := (val*16)+(c-"0")
    ELSEIF (c >= "a") AND (c <= "f") 
      val := (val*16)+(c-"a"+10)
    ELSEIF (c >= "A") AND (c <= "F")
      val := (val*16)+(c-"A"+10)
    ELSE 
      RETURN val
    ENDIF
    s++
  ENDWHILE
  RETURN val
ENDPROC

/* ------------------------------------------------------------------ */
/* Parse decimal string -> LONG                                        */
/* ------------------------------------------------------------------ */
PROC decval(s:PTR TO CHAR)
  DEF val = 0, c
  WHILE s[] <> 0
    c := s[]
    IF (c >= "0") AND (c <= "9")
      val := (val*10)+(c-"0")
    ELSE 
      RETURN val
    ENDIF
    s++
  ENDWHILE
  RETURN val
ENDPROC

/* ------------------------------------------------------------------ */
/* Concatenate src onto end of dst                                    */
/* ------------------------------------------------------------------ */
PROC strcat(dst:PTR TO CHAR, src:PTR TO CHAR)
  WHILE dst[] <> 0 DO dst++
  WHILE src[] <> 0
    dst[] := src[]
    dst++
    src++
  ENDWHILE
  dst[] := 0
ENDPROC

/* ------------------------------------------------------------------ */
/* Fill an array with zeros                                           */
/* ------------------------------------------------------------------ */

PROC zeromem(p:PTR TO CHAR, size)
  WHILE size > 0
    p[] := 0
    p++
    size--
  ENDWHILE
ENDPROC

/* ------------------------------------------------------------------ */
/* MAIN                                                               */
/* ------------------------------------------------------------------ */
PROC main()
  DEF wbmode   = FALSE,
      modeid   = DEF_MODEID,
      depth    = DEF_DEPTH,
      tdelay   = DEF_DELAY,
      keepopen = TRUE,
      cmdstart = -1,
      i        = 0,
      ntok     = 0,
      tp       = 0,
      done     = FALSE,
      rc       = 0,
      lastchar = 0,
      gfx      : PTR TO gfxbase,
      fr       : PTR TO filerequester,
      scr      : PTR TO screen,
      argstr   : PTR TO CHAR,
      p        : PTR TO CHAR,
      q        : PTR TO CHAR,
      tok      : PTR TO CHAR,
      tokens[64]: ARRAY OF LONG,
      tbuf[1024]: ARRAY OF CHAR,
      cmdbuf[1024]: ARRAY OF CHAR

  zeromem(tbuf, 1024)
  zeromem(tokens, 256)
  zeromem(cmdbuf, 1024)

  /* ------------------------------------------------------------------ */
  /* Determine launch context                                           */
  /* ------------------------------------------------------------------ */
  IF wbmessage <> NIL
    wbmode := TRUE
  ELSE
    /* CLI launch - parse arguments */
    argstr := arg
    IF argstr = NIL THEN argstr := ''
    WHILE (argstr[] = " ") OR (argstr[] = 9) DO argstr++

    /* ---------------------------------------------------------------- */
    /* If -? or ? comes in from CLI, print usage                        */
    /* ---------------------------------------------------------------- */
    IF strieq(argstr, '-?') OR strieq(argstr, '?')
      WriteF('RGBLaunch - Force RGB mode switch before launching a program\n\n')
      WriteF('Usage: RGBLaunch [SCREENMODE <hexid>] [DEPTH <n>] [DELAY <ticks>] [ASYNC] <cmd> [args]\n\n')
      WriteF('  SCREENMODE  Hex display mode ID (default: $0 = LORES 320x256)\n')
      WriteF('  DEPTH       Bitplanes 1-8 (default: 2)\n')
      WriteF('  DELAY       Ticks to wait after screen opens (default: 10)\n')
      WriteF('  ASYNC       Close stub screen before launching\n\n')
      WriteF('Common SCREENMODE values:\n')
      WriteF('  $20000  AGA PAL  LORES 320x256  (default)\n')
      WriteF('  $21000  AGA PAL  HIRES 640x256\n')
      WriteF('  $24000  AGA PAL  LORES 320x512 interlaced\n')
      WriteF('  $25000  AGA PAL  HIRES 640x512 interlaced\n')
      WriteF('  $09000  OCS/ECS PAL  LORES 320x256\n')
      WriteF('  $11000  OCS/ECS PAL  HIRES 640x256\n\n')
      WriteF('If no command is given, a file requester will open.\n')
      RETURN 0
    ENDIF

    /* ------------------------------------------------------------------ */
    /* Tokenise into tokens[] with storage in tbuf                        */
    /* ------------------------------------------------------------------ */
    p    := argstr
    done := FALSE
    WHILE (p[] <> 0) AND (p[] <> 10) AND (p[] <> 13) AND (done = FALSE)
      WHILE (p[] = " ") OR (p[] = 9) DO p++
      IF (p[] = 0) OR (p[] = 10) OR (p[] = 13)
        done := TRUE
      ELSE
        tokens[ntok] := tbuf+tp
        ntok++
        WHILE (p[] <> 0) AND (p[] <> " ") AND (p[] <> 9) AND (p[] <> 10) AND (p[] <> 13) AND (p[] <> "=")
          tbuf[tp] := p[]
          tp++
          p++
        ENDWHILE
        tbuf[tp] := 0
        tp++
        IF p[] = "=" THEN p++
      ENDIF
    ENDWHILE

    /* ------------------------------------------------------------------ */
    /* Detect NTSC                                                        */
    /* ------------------------------------------------------------------ */

    gfx := gfxbase
    IF gfx.displayflags AND NTSC
      modeid := modeid OR NTSC_MONITOR_ID
    ENDIF
    
    /* ------------------------------------------------------------------ */
    /* Parse keyword arguments until we hit the command                   */
    /* ------------------------------------------------------------------ */
    i    := 0
    done := FALSE
    WHILE (i < ntok) AND (done = FALSE)
      tok := tokens[i]
      IF strieq(tok, 'SCREENMODE') AND (i+1 < ntok)
        i++
        modeid := hexval(tokens[i])
      ELSEIF strieq(tok, 'DEPTH') AND (i+1 < ntok)
        i++
        depth := decval(tokens[i])
        IF depth < 1 THEN depth := 1
        IF depth > 8 THEN depth := 8
      ELSEIF strieq(tok, 'DELAY') AND (i+1 < ntok)
        i++
        tdelay := decval(tokens[i])
      ELSEIF strieq(tok, 'ASYNC')
        keepopen := FALSE
      ELSE
        cmdstart := i
        done     := TRUE
      ENDIF
      IF done = FALSE THEN i++
    ENDWHILE
  ENDIF
  
  /* ------------------------------------------------------------------ */
  /* No command given (or WB launch) - open ASL file requester          */
  /* ------------------------------------------------------------------ */
  IF cmdstart = -1
    aslbase := OpenLibrary('asl.library', 37)
    IF aslbase = NIL
      IF wbmode = FALSE THEN WriteF('RGBLaunch: Cannot open asl.library\n')
      RETURN 10
    ENDIF
    fr := AllocAslRequest(ASL_FILEREQUEST, [ASLFR_TITLETEXT, 'Select a program to run', TAG_END])
    IF fr = NIL
      IF wbmode = FALSE THEN WriteF('RGBLaunch: Could not allocate file requester\n')
      CloseLibrary(aslbase)
      RETURN 10
    ENDIF
    IF AslRequest(fr, NIL) = NIL
      FreeAslRequest(fr)
      CloseLibrary(aslbase)
      RETURN 0    /* user cancelled */
    ENDIF
    /* Build full path: drawer + separator if needed + file */
    cmdbuf[0] := 0
    strcat(cmdbuf, fr.drawer)
    /* Add path separator if drawer doesn't end in one */
    p := cmdbuf
    WHILE p[] <> 0 DO p++
    IF p > cmdbuf
      q := p-1
      lastchar := q[]
      IF (lastchar <> "/") AND (lastchar <> ":")
        p[] := "/"
        p++
        p[] := 0
      ENDIF
    ENDIF
    strcat(cmdbuf, fr.file)
    FreeAslRequest(fr)      
    CloseLibrary(aslbase)
    IF wbmode = FALSE THEN WriteF('RGBLaunch: Selected: \s\n', cmdbuf)
  ELSE
    /* ------------------------------------------------------------------ */
    /* Rebuild command string from remaining tokens                       */
    /* ------------------------------------------------------------------ */
    p := cmdbuf
    i := cmdstart
    WHILE i < ntok
      tok := tokens[i]
      WHILE tok[] <> 0
        p[] := tok[]
        p++
        tok++
      ENDWHILE
      IF i < (ntok-1)
        p[] := " "
        p++
      ENDIF
      i++
    ENDWHILE
    p[] := 0
  ENDIF

  /* ------------------------------------------------------------------ */
  /* Open native chipset screen to trigger p96 mode switch     */
  /* ------------------------------------------------------------------ */
  IF wbmode = FALSE
    WriteF('RGBLaunch: Opening native screen (mode $\h, depth \d)...\n', modeid, depth)
  ENDIF
  
  scr := OpenScreenTagList(NIL,
    [SA_DISPLAYID, modeid,
     SA_DEPTH,     depth,
     SA_SHOWTITLE, FALSE,
     SA_QUIET,     TRUE,
     SA_TYPE,      CUSTOMSCREEN,
     TAG_END])

  IF scr = NIL
    IF wbmode = FALSE 
      WriteF('RGBLaunch: WARNING - mode $\h failed, trying default fallback mode\n', modeid)
    ENDIF
    modeid := DEF_MODEID
    IF gfx.displayflags AND NTSC
      modeid := modeid OR NTSC_MONITOR_ID
    ENDIF   
    scr := OpenScreenTagList(NIL,
      [SA_DISPLAYID, modeid,
       SA_DEPTH,     DEF_DEPTH,
       SA_TYPE,      CUSTOMSCREEN,
       SA_SHOWTITLE, FALSE,
       SA_QUIET,     TRUE,
       SA_BEHIND,    TRUE,
       TAG_END])
    IF scr = NIL
      IF wbmode = FALSE
        WriteF('RGBLaunch: ERROR - Could not open any native screen, launching anyway\n')
      ENDIF
    ELSE
      /* Fallback screen opened - bring it forward so VideoCore sees it */
      ScreenToFront(scr)
      WaitTOF()
    ENDIF
  ENDIF

  /* Give Emu68 VideoCore time to notice and switch */
  IF tdelay > 0 AND wbmode = FALSE
    WriteF('RGBLaunch: Waiting \d ticks for mode switch to settle...\n', tdelay)
    Delay(tdelay)
  ENDIF

  /* In ASYNC mode, close stub screen before launching */
  IF keepopen = FALSE
    IF scr <> NIL
      CloseScreen(scr)
      scr := NIL
    ENDIF
    Delay(2)
  ENDIF

  /* ------------------------------------------------------------------ */
  /* Launch synchronously                                               */
  /* ------------------------------------------------------------------ */
  IF wbmode = FALSE 
    WriteF('RGBLaunch: Launching: \s\n', cmdbuf)
  ENDIF
  
  rc := SystemTagList(cmdbuf,
    [SYS_ASYNCH,    FALSE,
     SYS_USERSHELL, TRUE,
     TAG_END])

  /* ------------------------------------------------------------------ */
  /* Cleanup                                                            */
  /* ------------------------------------------------------------------ */
  IF scr <> NIL
    CloseScreen(scr)
    scr := NIL
  ENDIF

  IF rc = -1
    IF wbmode = FALSE
    WriteF('RGBLaunch: ERROR - Could not launch "\s"\n', cmdbuf)
    ENDIF
    RETURN 20
  ENDIF

  RETURN rc
ENDPROC
