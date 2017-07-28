//
//  Created by Gabriel Li on 2017/7/24.
//  Copyright © 2017年 木仓科技. All rights reserved.
//

#import "UIScrollView+AssignToWeak.h"
#import <objc/runtime.h>

static void _fixupAssginDelegate(Class cls);
static const char *s_delegate_ivar_name = NULL;

@implementation UIScrollView (AssignToWeak)

+ (void)load {
    _fixupAssginDelegate(self);
}

- (void)fixup_setDelegate:(id)delegate {
    NSLog(@"===== fixup_setDelegate:");
    Ivar ivar = class_getInstanceVariable([self class], s_delegate_ivar_name);
    object_setIvar(self, ivar, delegate);
    [self fixup_setDelegate:delegate];
}

- (id)fixup_delegate {
    NSLog(@"===== fixup_delegate");
    [self fixup_delegate];
    Ivar ivar = class_getInstanceVariable([self class], s_delegate_ivar_name);
    id del = object_getIvar(self, ivar);
    return del;
}

@end

#include <malloc/malloc.h>
#include <iterator>

template <typename Element, typename List, uint32_t FlagMask>
struct _mcc_entsize_list_tt {
    uint32_t entsizeAndFlags;
    uint32_t count;
    Element first;
    
    uint32_t entsize() const {
        return entsizeAndFlags & ~FlagMask;
    }
    uint32_t flags() const {
        return entsizeAndFlags & FlagMask;
    }
    
    Element& getOrEnd(uint32_t i) const {
        assert(i <= count);
        return *(Element *)((uint8_t *)&first + i*entsize());
    }
    Element& get(uint32_t i) const {
        assert(i < count);
        return getOrEnd(i);
    }
    
    size_t byteSize() const {
        return sizeof(*this) + (count-1)*entsize();
    }
    
    List *duplicate() const {
        return (List *)memdup(this, this->byteSize());
    }
    
    struct iterator;
    const iterator begin() const {
        return iterator(*static_cast<const List*>(this), 0);
    }
    iterator begin() {
        return iterator(*static_cast<const List*>(this), 0);
    }
    const iterator end() const {
        return iterator(*static_cast<const List*>(this), count);
    }
    iterator end() {
        return iterator(*static_cast<const List*>(this), count);
    }
    
    struct iterator {
        uint32_t entsize;
        uint32_t index;  // keeping track of this saves a divide in operator-
        Element* element;
        
        typedef std::random_access_iterator_tag iterator_category;
        typedef Element value_type;
        typedef ptrdiff_t difference_type;
        typedef Element* pointer;
        typedef Element& reference;
        
        iterator() { }
        
        iterator(const List& list, uint32_t start = 0)
        : entsize(list.entsize())
        , index(start)
        , element(&list.getOrEnd(start))
        { }
        
        const iterator& operator += (ptrdiff_t delta) {
            element = (Element*)((uint8_t *)element + delta*entsize);
            index += (int32_t)delta;
            return *this;
        }
        const iterator& operator -= (ptrdiff_t delta) {
            element = (Element*)((uint8_t *)element - delta*entsize);
            index -= (int32_t)delta;
            return *this;
        }
        const iterator operator + (ptrdiff_t delta) const {
            return iterator(*this) += delta;
        }
        const iterator operator - (ptrdiff_t delta) const {
            return iterator(*this) -= delta;
        }
        
        iterator& operator ++ () { *this += 1; return *this; }
        iterator& operator -- () { *this -= 1; return *this; }
        iterator operator ++ (int) {
            iterator result(*this); *this += 1; return result;
        }
        iterator operator -- (int) {
            iterator result(*this); *this -= 1; return result;
        }
        
        ptrdiff_t operator - (const iterator& rhs) const {
            return (ptrdiff_t)this->index - (ptrdiff_t)rhs.index;
        }
        
        Element& operator * () const { return *element; }
        Element* operator -> () const { return element; }
        
        operator Element& () const { return *element; }
        
        bool operator == (const iterator& rhs) const {
            return this->element == rhs.element;
        }
        bool operator != (const iterator& rhs) const {
            return this->element != rhs.element;
        }
        
        bool operator < (const iterator& rhs) const {
            return this->element < rhs.element;
        }
        bool operator > (const iterator& rhs) const {
            return this->element > rhs.element;
        }
    };
};

struct _mcc_ivar_t {
    int32_t *offset;
    const char *name;
    const char *type;
    uint32_t alignment_raw;
    uint32_t size;
};

struct _mcc_property_t {
    const char *name;
    const char *attributes;
};

struct _mcc_ivar_list_t : _mcc_entsize_list_tt<_mcc_ivar_t, _mcc_ivar_list_t, 0> {};
struct _mcc_property_list_t : _mcc_entsize_list_tt<_mcc_property_t, _mcc_property_list_t, 0> {};

__attribute__((always_inline))
static void _tryFree(const void *p) {
    if (p && malloc_size(p)) free((void *)p);
}

static inline void *_memdup(const void *mem, size_t len) {
    void *dup = malloc(len);
    memcpy(dup, mem, len);
    return dup;
}

static const char *_copyNonWeakIvarName(objc_property_t property) {
    if (!property) return NULL;
    unsigned int attrCount = 0;
    const char *ivarName = NULL; bool foundWeak = false;
    objc_property_attribute_t *attrs = property_copyAttributeList(property, &attrCount);
    for (unsigned int i = 0; i < attrCount; ++i) {
        objc_property_attribute_t attr = *(attrs+i);
        if (strcmp(attr.name, "W") == 0) {
            foundWeak = true;
            _tryFree(ivarName);
            break;
        } else if (strcmp(attr.name, "V") == 0 && attr.value) {
            ivarName = (const char *)_memdup(attr.value, strlen(attr.value)+1);
        }
    }
    return foundWeak ? NULL : ivarName;
}

static Class _findClassWithPropertyName(Class cls, const char *property_name) {
    objc_property_t prop = class_getProperty(cls, property_name);
    if (!prop) {
        return NULL;
    }
    const char *ivarName = _copyNonWeakIvarName(prop);
    if (!ivarName) {
        cls = class_getSuperclass(cls);
        while (cls) {
            prop = class_getProperty(cls, property_name);
            ivarName = _copyNonWeakIvarName(prop);
            if (ivarName) break;
            cls = class_getSuperclass(cls);
        }
    }
    s_delegate_ivar_name = ivarName;
    return ivarName ? cls : NULL;
}

static void _inferLayoutInfo(const uint8_t *layout, char *ivar_info, char type) {
    if (!layout || !ivar_info) {
        return;
    }
    ptrdiff_t index = 0; uint8_t byte;
    while ((byte = *layout++)) {
        unsigned skips = (byte >> 4);
        unsigned scans = (byte & 0x0F);
        index += skips;
        for (ptrdiff_t i = index; i < index+scans; ++i) {
            *(ivar_info+i) = type;
        }
        index = index+scans;
    }
}

// construct weak ivar and strong ivar layout
static char *_constructIvarInfos(Class cls, _mcc_ivar_list_t *ivar_list) {
    if (!cls || !ivar_list) {
        return NULL;
    }
    uint32_t ivarCount = ivar_list->count;
    char *ivarInfo = (char *)calloc(ivarCount+1, sizeof(char));
    memset(ivarInfo, 'A', ivarCount);
    const uint8_t *ivarLayout = class_getIvarLayout(cls);
    _inferLayoutInfo(ivarLayout, ivarInfo, 'S');
    const uint8_t *weakLayout = class_getWeakIvarLayout(cls);
    _inferLayoutInfo(weakLayout, ivarInfo, 'W');
    return ivarInfo;
}

static const uint8_t *_fixupIvarLayout(const uint8_t *orig_layout, const char *ivar_info, uint32_t count, char type) {
    if (!ivar_info) {
        return NULL;
    }
    uint8_t *layout = (uint8_t *)calloc(count+1, 1);
    ptrdiff_t index = 0;
    uint32_t miss = 0; uint32_t hit = 0;
    for (uint32_t i = 0; i < count; ++i) {
        char byte = *(ivar_info+i);
        char next = *(ivar_info+i+1);
        if (byte != type) {
            ++miss;
            if (miss >= 0x0F && next == type) {
                while (miss >= 0x0F) {
                    *(layout+index++) = 0xF0;
                    miss -= 0x0F;
                }
                if (miss > 0) {
                    *(layout+index++) = (miss << 4);
                    miss = 0;
                }
                hit = 0;
            }
        } else {
            ++hit;
            if (hit == 0x0F || next != type) {
                uint8_t val = (uint8_t)((miss << 4) + hit);
                val > 0 ? (*(layout+index++) = val) : NULL;
                miss = 0; hit = 0;
            }
        }
    }
    if (index == 0) {
        return NULL;
    }
    if (index+1 < count) {
        uint8_t *tmp = (uint8_t *)calloc(index+1, 1);
        memcpy(tmp, layout, index);
        layout = tmp;
    }
    if (orig_layout && !memcmp(orig_layout, layout, malloc_size(layout))) {
        free(layout);
        layout = NULL;
    }
    return layout;
}

static void _fixupSelector(Class cls, SEL origSel, SEL fixSel) {
    Method setter = class_getInstanceMethod(cls, origSel);
    Method fixSetter = class_getInstanceMethod(cls, fixSel);
    BOOL success = class_addMethod(cls, origSel, method_getImplementation(fixSetter), method_getTypeEncoding(fixSetter));
    if (success) {
        class_replaceMethod(cls, fixSel, method_getImplementation(setter), method_getTypeEncoding(setter));
    } else {
        method_exchangeImplementations(setter, fixSetter);
    }
}

static void _fixupAssginDelegate(Class cls) {
    Class origCls = cls;
    // find class(and superclasses) that contains the named property
    cls = _findClassWithPropertyName(cls, "delegate");
    if (!cls) return;
    
    struct {
        Class isa;
        Class superclass;
        struct {
            void *_buckets;
#if __LP64__
            uint32_t _mask;
            uint32_t _occupied;
#else
            uint16_t _mask;
            uint16_t _occupied;
#endif
        } cache;
        uintptr_t bits;
    } *objcClass = (__bridge typeof(objcClass))cls;
    
#if !__LP64__
#define FAST_DATA_MASK 0xfffffffcUL
#else
#define FAST_DATA_MASK 0x00007ffffffffff8UL
#endif
    struct {
        uint32_t flags;
        uint32_t version;
        struct {
            uint32_t flags;
            uint32_t instanceStart;
            uint32_t instanceSize;
#ifdef __LP64__
            uint32_t reserved;
#endif
            const uint8_t *ivarLayout;
            
            const char *name;
            void *baseMethodList;
            void *baseProtocols;
            const _mcc_ivar_list_t *ivars;
            
            const uint8_t *weakIvarLayout;
            _mcc_property_list_t *baseProperties;
        } *ro;
    } *objcRWClass = (typeof(objcRWClass))(objcClass->bits & FAST_DATA_MASK);
    
    // check if contains ivars
    _mcc_ivar_list_t *ivarList = (_mcc_ivar_list_t *)objcRWClass->ro->ivars;
    if (!ivarList || !ivarList->count) {
        return;
    }
    
    // make sure class is ARC-able
#define RO_IS_ARC 1<<7
    objcRWClass->ro->flags |= RO_IS_ARC;
#define RW_CONSTRUCTING (1<<26)
    objcRWClass->flags |= RW_CONSTRUCTING;
    
    // find named ivar from ivar list
    _mcc_ivar_t *ivar = NULL;
    uint32_t ivarPos = 0;
    for (_mcc_ivar_list_t::iterator it = ivarList->begin(); it != ivarList->end(); ++it, ++ivarPos) {
        if (it->name  &&  0 == strcmp(s_delegate_ivar_name, it->name)) {
            ivar = &*it;
            break;
        }
    }
    // the named ivar doesn't exists in class
    if (!ivar) {
        return;
    }
    // construct ivar layout infos
    char *ivarInfo = _constructIvarInfos(cls, ivarList);
    if (!ivarInfo) {
        return;
    }
#if DEBUG == 1
    printf("before fixup: %s\n", ivarInfo);
#endif
    // assign -> weak
    (*(ivarInfo+ivarPos) == 'A') ? (*(ivarInfo+ivarPos) = 'W') : NULL;
#if DEBUG == 1
    printf("after fixup: %s\n", ivarInfo);
#endif
    
    // fixup strong ivar layout
    const uint8_t *ivarLayout = _fixupIvarLayout(objcRWClass->ro->ivarLayout, ivarInfo, ivarList->count, 'S');
    if (ivarLayout) {
        class_setIvarLayout(cls, ivarLayout);
    }
    // fixup weak ivar layout
    const uint8_t *weakLayout = _fixupIvarLayout(objcRWClass->ro->weakIvarLayout, ivarInfo, ivarList->count, 'W');
    if (weakLayout) {
        class_setWeakIvarLayout(cls, weakLayout);
    }
    free((void *)ivarInfo);
    // clear constructing flag after ivar layout changed
    objcRWClass->flags &= ~RW_CONSTRUCTING;
    // swizzling setter finally
    _fixupSelector(origCls, @selector(setDelegate:), @selector(fixup_setDelegate:));
    _fixupSelector(origCls, @selector(delegate), @selector(fixup_delegate));
}
