T x(T)(T i)
{
	return i + 1;
}

T y(T)(T i)
{
	return i;
}

pragma(msg, 10000002.x.y.x!int.y!int.x!(int).y!(int).x!int().y!int().x!(int)().y!(int)());