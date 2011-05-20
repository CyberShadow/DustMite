/// Very simplistic D source code "parser"
module dsplit;

import std.file;
import std.path;
import std.string;

struct Entity
{
	string text;   // declaration etc., also filename
	string header; // scope-opening character ( { ), including whitespace
	Entity[] children;
	string footer; // terminating or scope-closing character ( } or ; ), including whitespace
}

Entity[] loadFiles(string dir)
{
	Entity[] set;
	foreach (path; listdir(dir, "*"))
		if (isfile(path))
		{
			assert(path.startsWith(dir));
			auto name = path[dir.length+1..$];
			set ~= Entity(name, null, loadFile(path), null);
		}
	return set;
}

private:

Entity[] loadFile(string path)
{
	string contents = cast(string)read(path);
	switch (getExt(path))
	{
	case "d":
		return parseD(contents);
	// One could add custom splitters for other languages here - for example, a simple line/word/character splitter for most text-based formats
	default:
		return [Entity(contents, null, null, null)];
	}
}

Entity[] parseD(string s)
{
	alias immutable(char)* P;

	s = ("\0\0\0"~s~"\0")[3..$-1];
	P p = s.ptr, lastFooterStart;
	static string slice(P p0, P p1) { return p0[0..p1-p0]; }

	/// Moves p forward over first series of EOL characters, or until first non-whitespace character
	void skipEOL()
	{
		while (iswhite(*p))
		{
			if (*p == '\r' || *p == '\n')
			{
				while (*p == '\r' || *p == '\n')
					p++;
				return;
			}
			p++;
		}
	}

	Entity[] parseScope(bool topLevel)
	{
		Entity entity;
		P start = p;
		P wsStart = p;
		Entity[] result;

		void addEntity(P textEnd, P headerEnd, Entity[] entities, P footerStart)
		{
			result ~= Entity(slice(start, textEnd), headerEnd ? slice(textEnd, headerEnd) : null, entities, footerStart ? slice(footerStart, p) : null);
			start = wsStart = p;
		}

		while (true)
		{
			switch (*p)
			{
				case ';': // end of entity
				{
					auto entityEnd = p;
					p++; skipEOL();
					addEntity(entityEnd, null, null, entityEnd);
					break;
				}
				case '{':
				{
					auto textEnd = wsStart;
					p++; skipEOL();
					auto headerEnd = p;
					auto entities = parseScope(false);
					skipEOL();

					addEntity(textEnd, headerEnd, entities, lastFooterStart);
					break;
				}
				case '}':
				{
					if (topLevel) // stray } or bug, treat as normal character
					{
						p++;
						wsStart = p;
						break;
					}

					if (start != wsStart)
					{
						// there was some unterminated stuff at the end of the current scope
						// TODO: EOL separation here
						addEntity(p, null, null, null);
					}
					lastFooterStart = start;
					p++;
					return result;
				}
				case '\0':
				{
					if (start != p)
						addEntity(p, null, null, null);
					return result;
				}
				case '\'':
				{
					p++;
					if (*p == '\\')
						p++;
					while (*p != '\'')
						p++;
					p++;
					wsStart = p;
					break;
				}
				case '"':
				{
					if (*(p-1) == 'r')
					{
						p++;
						while (*p != '"')
							p++;
						p++;
					}
					else
					{
						p++;
						while (*p != '"')
						{
							if (*p == '\\')
								p += 2;
							else
								p++;
						}
						p++;
					}
					wsStart = p;
					break;
				}
				case '`':
				{
					p++;
					while (*p != '`')
						p++;
					p++;
					wsStart = p;
					break;
				}
				case '/':
				{
					p++;
					if (*p == '/')
					{
						while (*p != '\r' && *p != '\n')
							p++;
					}
					else
					if (*p == '*')
					{
						p+=3;
						while (*(p-2) != '*' && *(p-1) != '/')
							p++;
					}
					else
					if (*p == '+')
					{
						p++;
						int commentLevel = 1;
						while (commentLevel)
						{
							if (*p == '/' && *(p+1)=='+')
								commentLevel++, p+=2;
							else
							if (*p == '+' && *(p+1)=='/')
								commentLevel--, p+=2;
							else
								p++;
						}
					}
					else
						p++;
				}
				// TODO: token strings
				// TODO: parens
				// TODO: lists?
				default:
				{
					def:
					if (!iswhite(*p))
						wsStart = p+1;
					p++;
					break;
				}
			}

		}
	}

	return parseScope(true);
}
