int f(int i)
{
	if (i > -1 && i < 1)
	{
		return 0;
	}
	return i * i;
}

pragma(msg, f(5) == 30);
