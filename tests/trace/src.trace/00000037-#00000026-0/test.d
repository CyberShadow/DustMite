int f(int i)
{
	if (i == 0)
	return i * f(i - 1);
}

pragma(msg, f(5) == 120);
