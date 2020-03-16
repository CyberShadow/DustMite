int f(int i)
{
	return i * f(i - 1);
}

pragma(msg, f(5) == 120);
