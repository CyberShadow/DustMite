int f(int i)
{
	if (0)
		return 1;
	return i * f(i - 1);
}

pragma(msg, f(5) == 120);
