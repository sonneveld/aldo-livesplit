state("DOSBox")
{
}

startup
{
    refreshRate = 60;
}

init
{
	version = modules.First().FileVersionInfo.ProductVersion;

    vars.next_split_at_level = 1;

    IntPtr ptr; 
    uint membase = 0;


    /*
    Find the MemBase ptr in Dosbox
    Tested against 0.73, 0.74, 0.74-2, 0.74-3
    */

    foreach (var page in game.MemoryPages(true)) {
        var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
        ptr = scanner.Scan(new SigScanTarget(2,
            "C3 A1 ?? ?? ?? ??     C3      8D 76  00 8D BC 27 00 00 00 00      8b 15"
        ));
        if (ptr != IntPtr.Zero) { 
            membase =  memory.ReadValue<uint>(ptr) - (uint)modules.First().BaseAddress;
            break;
        }
    }

    if (membase == 0) {
        throw new Exception("Couldn't find dosbox membase!");
    }

    // print("membase: dosbox.exe+0x" + membase.ToString("X"));
    uint membasevalue = memory.ReadValue<uint>((IntPtr)(membase + (uint)modules.First().BaseAddress));


    // Use the distinct jump table data to find our way to the data segment base.
    var scanner2 = new SignatureScanner(game, (IntPtr)(membasevalue), 0x10000);
    IntPtr jumptable_ptr = scanner2.Scan(new SigScanTarget(0,
        "00 00  FC FF FC FF FC FF FC FF FC FF FC FF  FE FF FE FF FE FF FE FF FE FF  00 00"
    ));
    if (jumptable_ptr == IntPtr.Zero) {
        throw new Exception("Couldn't find aldo jump table!");
    }

    // search for text strings to determine aldo version
    int aldo_version = 10;

    var scanner_aldo3 = new SignatureScanner(game, (IntPtr)(membasevalue), 0x10000);
    IntPtr aldo3_instruction = scanner_aldo3.Scan(new SigScanTarget(0,
        // "Press J now for special instructions"
        "50 72 65 73 73 20 4A 20 6E 6F 77 20 66 6F 72 20 73 70 65 63 69 61 6C 20 69 6E 73 74 72 75 63 74 69 6F 6E 73 2E"
    ));
    if (aldo3_instruction != IntPtr.Zero) {
        aldo_version = 3;
    }

    var scanner_aldo2 = new SignatureScanner(game, (IntPtr)(membasevalue), 0x10000);
    IntPtr aldo2_instruction = scanner_aldo2.Scan(new SigScanTarget(0,
        // "(Fire Ball and Mountain Pass for example)"
        "28 46 69 72 65 20 42 61 6C 6C 20 61 6E 64 20 4D 6F 75 6E 74 61 69 6E 20 50 61 73 73 20 66 6F 72 20 65 78 61 6D 70 6C 65 29"
    ));
    if (aldo2_instruction != IntPtr.Zero) {
        aldo_version = 2;
    }

    var scanner_aldo11 = new SignatureScanner(game, (IntPtr)(membasevalue), 0x10000);
    IntPtr aldo11_instruction = scanner_aldo11.Scan(new SigScanTarget(0,
        // "Two new boards."
        "54 77 6F 20 6E 65 77 20 62 6F 61 72 64 73 2E"
    ));
    if (aldo11_instruction != IntPtr.Zero) {
        aldo_version = 11;
    }

    print("aldo v" + aldo_version + " detected."); 


    uint dseg_ptr;
    switch(aldo_version) {
        case 10:
            dseg_ptr = (uint)jumptable_ptr - 0x40;
            break;
        case 11:
            dseg_ptr = (uint)jumptable_ptr - 0x41;
            break;
        case 2:
            dseg_ptr = (uint)jumptable_ptr - 0x42;
            break;
        case 3:
            dseg_ptr = (uint)jumptable_ptr - 0x44;
            break;
        default:
            throw new Exception("Unknown Aldo version!");
    }


    uint dseg_offset = (uint)dseg_ptr - membasevalue;
    // print("jumptable: dosbox.exe+membase+0x" + dseg_offset.ToString("X"));
    

    // Create watchers

    int ALDO_END_GAME_OFFSET;
    int ALDO_LEVEL_OFFSET;
    int ALDO_KB_INT_OFFSET;

    switch(aldo_version) {
        case 10:
        case 11:
            ALDO_END_GAME_OFFSET = 0x2d;
            ALDO_LEVEL_OFFSET = 0x2e;
            ALDO_KB_INT_OFFSET = 0x33;
            break;
        case 2:
        case 3:
            ALDO_END_GAME_OFFSET = 0x2e;
            ALDO_LEVEL_OFFSET = 0x2f;
            ALDO_KB_INT_OFFSET = 0x34;
            break;
        default:
            throw new Exception("Unknown Aldo version!");
    }


    switch(aldo_version) {
        case 10:
            vars.ALDO_NUM_LEVELS = 10;
            break;
        case 11:
            vars.ALDO_NUM_LEVELS = 12;
            break;
        case 2:
            vars.ALDO_NUM_LEVELS = 10;
            break;
        case 3:
            vars.ALDO_NUM_LEVELS = 10;
            break;
        default:
            throw new Exception("Unknown Aldo version!");
    }


    vars.end_game_w = new MemoryWatcher<byte>(new DeepPointer( (IntPtr) (dseg_ptr + ALDO_END_GAME_OFFSET)));
    vars.current_level_w = new MemoryWatcher<byte>(new DeepPointer( (IntPtr) (dseg_ptr + ALDO_LEVEL_OFFSET)));
    vars.orig_kb_int_w = new MemoryWatcher<byte>(new DeepPointer( (IntPtr) (dseg_ptr + ALDO_KB_INT_OFFSET)));
}

update
{
    vars.end_game_w.Update(game);
    vars.current_level_w.Update(game);
    vars.orig_kb_int_w.Update(game);
}

reset
{
    return vars.orig_kb_int_w.Current == 0; 
}

start
{
    if (vars.orig_kb_int_w.Current != 0) {
        vars.next_split_at_level = 1;
        return true;
    }
    return false;
}

split
{
    if (vars.current_level_w.Current == vars.next_split_at_level) {
        vars.next_split_at_level = (vars.next_split_at_level + 1) % vars.ALDO_NUM_LEVELS;
        return true;
    }
    // Need to take into account the "Congrats" screen for aldo 2/3. We don't increment level so
    // need to detect split some other way.
    if (vars.end_game_w.Old != vars.end_game_w.Current && vars.end_game_w.Current == 1) {
        return true;
    }
    return false;
}
