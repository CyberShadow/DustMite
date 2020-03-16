/// Polynomial hash for partial rehashing.
/// http://stackoverflow.com/a/42112687/21501
/// Written by Vladimir Panteleev <vladimir@thecybershadow.net>
/// Released into the Public Domain

module polyhash;

import std.range.primitives;
import std.traits;

struct PolynomialHash(Value)
if (isUnsigned!Value)
{
	Value value;   /// The hash value of the hashed string
	size_t length; /// The length of the hashed string

	// Cycle length == 2^^30 for uint, > 2^^46 for ulong
	// TODO: find primitive root modulo 2^^32, if one exists
	enum Value p = 269;

	/// Return p^^power (mod q).
	static Value pPower(size_t power)
	{
		/// Precalculated table for (p^^(2^^i))
		static immutable Value[size_t.sizeof * 8] power2s = (){
			Value[size_t.sizeof * 8] result;
			Value v = p;
			foreach (i; 0 .. result.length)
			{
				result[i] = v;
				v *= v;
			}
			return result;
		}();

		Value v = 1;
		foreach (b; 0 .. power2s.length)
			if ((size_t(1) << b) & power)
				v *= power2s[b];
		return v;
	}

	void put(char c)
	{
		value *= p;
		value += Value(c);
		length++;
	}

	void put(in char[] s)
	{
		foreach (c; s)
		{
			value *= p;
			value += Value(c);
		}
		length += s.length;
	}

	void put(ref typeof(this) hash)
	{
		value *= pPower(hash.length);
		value += hash.value;
		length += hash.length;
	}

	static typeof(this) hash(T)(T value)
	if (is(typeof({ typeof(this) result; .put(result, value); })))
	{
		typeof(this) result;
		.put(result, value);
		return result;
	}

	unittest
	{
		assert(hash("").value == 0);
		assert(hash([hash(""), hash("")]).value == 0);

		// "a" + "" + "b" == "ab"
		assert(hash([hash("a"), hash(""), hash("b")]) == hash("ab"));

		// "a" + "bc" == "ab" + "c"
		assert(hash([hash("a"), hash("bc")]) == hash([hash("ab"), hash("c")]));

		// "a" != "b"
		assert(hash("a") != hash("b"));

		// "ab" != "ba"
		assert(hash("ab") != hash("ba"));
		assert(hash([hash("a"), hash("b")]) != hash([hash("b"), hash("a")]));

		// Test overflow
		assert(hash([
			hash("Mary"),
			hash(" "),
			hash("had"),
			hash(" "),
			hash("a"),
			hash(" "),
			hash("little"),
			hash(" "),
			hash("lamb"),
			hash("")
		]) == hash("Mary had a little lamb"));
	}
}

unittest
{
	PolynomialHash!uint uintTest;
	PolynomialHash!ulong ulongTest;
}
