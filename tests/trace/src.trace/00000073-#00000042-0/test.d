int f(int i)
{
	if (i == 0)
		return 1;
	return i * f(1);
}

pragma(msg, f(5) == 120);
