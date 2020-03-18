import i : ione = one;
import m;
enum unused = 1;
enum used = 1;
pragma(msg, one + ione + m.one + used == 4);
