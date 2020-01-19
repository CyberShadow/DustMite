auto pp(int a, int b)
{
    return a^^b;
}

// DustMiteNoRemoveStart
unittest
{
    assert(pp(3,4) == 81);
}
