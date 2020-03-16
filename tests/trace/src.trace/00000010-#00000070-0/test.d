int f(int i)
{
	if (i == 0)
	{
		return 1;
	}
	return i * f(i - 1);
}

pragma(msg);
