state("DOSBox", "0, 74, 3, 0")
{
    ulong membase : "DOSBox.exe", 0x193C370;
    // dseg: 0x1B20
    byte timer_start_value : "DOSBox.exe", 0x193C370, 0x1B21;
    byte level : "DOSBox.exe", 0x193C370, 0x1B4e;
    ulong orig_kb_int : "DOSBox.exe", 0x193C370, 0x1B43;
}

init
{
	version = modules.First().FileVersionInfo.ProductVersion;
    vars.current_level = 0;
    // refreshRate = 60;
}

reset
{
    return current.orig_kb_int == 0; 
}

start
{
    vars.current_level = 0;
    return current.orig_kb_int != 0;
}

split
{
    int next_level = (vars.current_level + 1) % 10;
    if (current.level == next_level) {
        vars.current_level = next_level;
        return true;
    }
    return false;
}
