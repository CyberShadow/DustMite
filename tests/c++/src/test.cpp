# 1 "<built-in>" 1
# 171 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/x86_64-linux-gnu/bits/c++config.h" 3
namespace {
typedef long size_t;
}
# 71 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/bits/stl_algobase.h" 3

namespace __attribute__ (())
{
template<typename _CharT>
    struct char_traits;
}
#pragma 3

namespace __gnu_cxx __attribute__ (())
{

template<typename _Tp>
    class new_allocator
    {
public:
      ;
typedef _Tp value_type;

template<typename _Tp1>
        struct rebind
        { typedef new_allocator<_Tp1> other; };
};
}
# 35 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/x86_64-linux-gnu/bits/c++allocator.h" 3

namespace std __attribute__ (())
{
template<typename _Tp>
    class allocator: public __gnu_cxx::new_allocator<_Tp>
    {
};
}
# 64 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/map" 3
# 1 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/bits/stringfwd.h" 3

namespace std __attribute__ (())
{
template<typename _CharT, typename = char_traits<_CharT>,
typename = allocator<_CharT> >
    class basic_string;

typedef basic_string<char> string;
}
# 42 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/bits/basic_string.h" 3

namespace std __attribute__ (())
{
template<typename _CharT, typename , typename _Alloc>
    class basic_string
    {
public:
      basic_string() { }

basic_string(_CharT* , const _Alloc& = _Alloc());
};
}

# 36 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/bits/alloc_traits.h" 3

namespace std __attribute__ (())
{
template<typename _Alloc, typename _Tp>
    class __alloctr_rebind_helper
    {
template<typename , typename _Tp2>
 static bool
        _S_chk(){ }
public:
      static const bool __value = _S_chk<_Alloc, _Tp>;
};

template<typename _Alloc, typename _Tp,
bool = __alloctr_rebind_helper<_Alloc, _Tp>::__value>
    struct __alloctr_rebind;

template<typename _Alloc, typename _Tp>
    struct __alloctr_rebind<_Alloc, _Tp, true>
    {
typedef typename _Alloc::template rebind<_Tp>::other __type;
};

template<typename _Alloc>
    struct allocator_traits
    {

typedef typename _Alloc::value_type value_type;
static value_type* _S_pointer_helper(); typedef decltype(_S_pointer_helper()) __pointer; typedef __pointer pointer;

template<typename _Tp>
        using rebind_alloc = typename __alloctr_rebind<_Alloc, _Tp>::__type;
};

}
namespace __gnu_cxx __attribute__ (())
{
template<typename _Alloc>
  struct __alloc_traits  : std::allocator_traits<_Alloc>
  {
typedef std::allocator_traits<_Alloc> _Base_type;
template<typename _Tp>
      struct rebind
      { typedef typename _Base_type::template rebind_alloc<_Tp> other; };
};

}
# 65 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/vector" 3
# 67 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/bits/stl_vector.h" 3
namespace std __attribute__ (())
{
template<typename _Tp, typename _Alloc>
    struct _Vector_base
    {
typedef typename __gnu_cxx::__alloc_traits<_Alloc>::template
        rebind<_Tp>::other _Tp_alloc_type;
typedef typename __gnu_cxx::__alloc_traits<_Tp_alloc_type>::pointer
        pointer;

struct _Vector_impl
      : _Tp_alloc_type
      {
pointer _M_start;
pointer _M_finish;
pointer _M_end_of_storage;
};
_Vector_impl _M_impl;

void   _M_deallocate(pointer __p, size_t )
{
if (__p)
;
}

};
template<typename _Tp, typename _Alloc = std::allocator<_Tp> >
    class vector : _Vector_base<_Tp, _Alloc>
    {
typedef _Vector_base<_Tp, _Alloc> _Base;
typedef _Tp value_type;
typedef size_t size_type;
using _Base::_M_deallocate;
public:
      vector() { }

size_type  size() { return this->_M_impl._M_finish - this->_M_impl._M_start; }

void    push_back(const value_type& )
{
++this->_M_impl._M_finish;
_M_emplace_back_aux();
}

template<typename... _Args>
        void
        _M_emplace_back_aux(_Args&&... );
};
}
# 67 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/vector" 3
# 60 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/bits/vector.tcc" 3
namespace std __attribute__ (())
{
template<typename _Tp, typename _Alloc>
    template<typename... _Args>
      void
      vector<_Tp, _Alloc>::
      _M_emplace_back_aux(_Args&&... )
{
	try {}
	catch(...){}
	_M_deallocate(this->_M_impl._M_start,
	this->_M_impl._M_end_of_storage
		    - this->_M_impl._M_start);
}
}

# 71 "/usr/lib/gcc/x86_64-linux-gnu/4.7/../../../../include/c++/4.7/vector" 3

class __attribute__(()) QByteArray
{
public:
    ;
char *constData() ;
};

class __attribute__(()) QString
{
public:
    ;
QByteArray toLocal8Bit() ;
};

template <typename T>
class QList
{
public:
    QList() { }
class const_iterator {
public:
        ;
	T &operator*() { }
	bool operator!=(const_iterator ) { }
	};
	const_iterator constBegin() { }
	const_iterator constEnd() { }
};

class QStringList : public QList<QString>
{
};

class __attribute__(()) QDir
{
public:
    enum { };
QStringList entryList() ;
};

void foo (const std::string& , const std::string& , std::vector<std::string>& vlist)
{
	QDir d;
	QStringList entries = d.entryList();

	for (QStringList::const_iterator iter = entries.constBegin(); iter != entries.constEnd(); )
	vlist.push_back((*iter).toLocal8Bit().constData());
	if(vlist.size())
	;
}

# 12 \
    "34"
