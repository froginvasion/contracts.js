var contracts = window["contracts-js"];
contracts.autoload();

var server = "server";
var client = "client";


module("Basic Contracts");


test("checking id", function() {
    var id = guard(
        fun(Num, Num),
        function(x) { return x; });

    ok(id(3));
    raises(function() { id("foo"); });
    var f = 42;
    // id("foo");
});

test("names of contracts", function() {
    equal(Str.cname, "Str");
    equal(Num.cname, "Num");
    // todo: fix
    // equal(M.idObj.id.__cname, "Number -> Number");
});

test("multiple args for function contracts", function() {
    var f1 = function(a, b, c) { return a + 1; };
    var f2 = function(a, b, c) { return b + "foo"; };
    var f3 = function(a, b, c) { return c; };
    var f1c = guard(
        fun([Num, Str, Bool], Num),
        f1);
    var f2c = guard(
        fun([Num, Str, Bool], Str),
        f2);
    var f3c = guard(
        fun([Num, Str, Bool], Str),
        f3);

    equal(f1c(1, "foo", false), 2);
    equal(f2c(1, "foo", false), "foofoo");
    raises(function() { f1c("foo", 1, false); }, "bad client");
    raises(function() { f2c("foo", 1, false); }, "bad client");
    raises(function() { f3c(1, "foo", false); }, "bad server");
});

test("optional args for functions", function() {
    var f = guard(
        fun([Num, opt(Str)], Num),
        function(x, y) { return x; });

    ok(f(42), "the one arg works");
    ok(f(42, "hello"), "can use the optional arg");
    raises(function() { f(42, 42); }, "broken contract on optional arg");

    raises(function() {
        guard(fun([Num, opt(Str), Bool], Num),
              function(x) { return x; });
    }, "cannot guard with a required arg after an optional arg");
});

test("higher order functions", function() {
    var id = function(x) { return x; };
    var pred = guard(
        fun([fun(Bool, Bool), Bool], Bool),
        function(p, x) { return p(x); });

    ok(pred(id, true), "higher order works");
    raises(function () { pred(id, 42); }, "client broke contract");

    var pred_client_ho = guard(
        fun([fun(Bool, Str), Bool], Bool),
        function(p, x) { return p(x); });
    raises(function () { pred_client_ho(id, true); }, "client broke contract");
    raises(function () { pred_client_ho(function(x) { return "foo"; }, true); }, "server broke contract");

    var pred_server_ho = guard(
        fun([fun(Str, Bool), Bool], Bool),
        function(p, x) { return p(x); });
    raises(function () { pred_server_ho(id, true); }, "server broke contract");
});

test("dependent functions", function() {
    var id = guard(
        fun(Str, function(arg) { return check(function(r) { return arg === r; }, "id===id"); }),
        function(x) { return x; });

    ok(id("foo"), "id really is id");

    var not_id = guard(
        fun(Str, function(arg) { return check(function(r) { return arg === r; }, "id===id"); }),
        function(x) { return x + "foo"; });
    raises(function() { not_id("foo"); }, "violates dependent contract");
});


test("basic functions", function() {
    // some of this is duped from above
    var id = function(x) { return x; };
    var idc = guard(fun(Num, Num), id);
    same(idc(4), 4,
         "id obeys contract");
    raises(function() { idc("foo"); },
           "id breaks contract");


    var id_nonew = guard(
        fun(Num, Num, {callOnly: true}),
        id);
    same(id_nonew(4), 4,
         "nonew obeys contract");
    raises(function() { new id_nonew(4); },
           "nonew obeys contract but called by new");

    raises(function() { id_nonew("foo"); },
           "nonew breaks contract");
    raises(function() { new id_nonew("foo"); },
           "no newbreaks contract and called by new"); // todo: distinguish in blame message

});

test("constructor contracts", function() {
    var good_ctor = guard(
        ctor(Str, object({a: Str, b: Num})),
        function(s) { this.a = s; this.b = 42; });
    raises(function() { good_ctor("foo"); },
           "onlynew obeys contract but not called with new");
    ok(new good_ctor("foo"),
         "onlynew obeys contract and called by new");

    var bad_ctor = guard(
        ctor(Num, object({a: Str, b: Num})),
        function(s) { this.a = 42; this.b = s; });
    raises(function() { new bad_ctor("foo"); } );
    var safe_ctor = guard(
        ctorSafe(Str, object({a: Str, b:Num})),
        function(s) { this.a = s; this.b = 42; });
    ok(new safe_ctor("foo"), "can call with new");
    ok((new safe_ctor("foo")).a, "can call with new and get prop");
    ok(safe_ctor("foo"), "can call without new");
});

test("call/new have different contracts", function() {
    var ctor_call = guard(
        fun({
            call: [Num, object({a: Str, b: Num})],
            new: [Str, object({a: Str, b: Num})]
        }),
        function(x) {
            if(typeof(x) === "number") {
                this.a = "foo";
                this.b = x;
            } else {
                this.a = x;
                this.b = 42;
            }
            return this;
        });
    same(ctor_call(222).b, 222, "calling works for combined ctor/call");
    raises(function() { ctor_call("hello"); }, "broken contract for calling in combined ctor/call");
    same(new ctor_call("hello").a, "hello", "new works for combined ctor/call");
    raises(function() { new ctor_call(42); }, "broken contract for new in combined ctor/call");
});

test("this contract on functions", function() {
    var f = guard(
        fun(Str, Str,
            { this: object({ a: Str, b: Num })}),
        function(s) { return this.a + this.b; });

    o = {a: "foo", b: 42, fun: f};
    same(o.fun("foo"), "foo42", "obeys contract");
    raises(function() { f("foo"); }, "fails contract");
});


test("can contract for both function + objects properties", function() {
    var id = function(x, y) { return x; };
    ok(id(4) === 4);
    ok(id.length === 2);
    var idc = guard(
        and(
            fun(Str, Str),
            object({ length: Str })),
        id);
    raises(function() { idc(4) === 4; });
    raises(function() { idc.length; });
});

test("checking Lists", function() {

    // raises(function() { guard(List, {length: 3}, server, client); },
    //        "not a list but looks like it");

    // var jsarr = guard(JsArray, [1,2,3], server, client);
    // ok(jsarr[0] = 4, "js arrays are mutable");
    // ok(delete jsarr[1], "js arrays can have holes");

    // var l = Object.freeze([1,2,3]);
    // var lc = guard(List, l, server, client);
    // ok(lc[0]);

    // raises(function() { lc[0] = 4; },
    //        "lists are immutable");

    // raises(function() { delete lc[0]; },
    //        "cannot delete list elements");

    // var hole_l = [1,2,3];
    // delete hole_l[1];
    // hole_l = Object.freeze(hole_l);
    // raises(function() { guard(List, hole_l, server, client);  },
    //        "lists have no holes");

    // var undef_l = Object.freeze([1,undefined, 3]);
    // ok(guard(List, undef_l, server, client),
    //    "lists can have undefined");

    // var sl = [1,2,3];
    // delete sl[2];
    // sl = Object.freeze(sl);
    // raises(function() { guard(SaneArray, sl, server, client); },
    //        "can't contract a sane array with holes");

    // var saneArr = guard(SaneArray, [1,2,3], server, client);
    // ok(saneArr[1] = 44,
    //    "sane arrays are mutable");
    // raises(function() { delete saneArr[1]; },
    //        "sane arrays can't have holes");

});

test("checking sealed/frozen objects", function() {
    var o = Object.seal({x:3});
    ok(guard(
        object({ x: Num }, {sealed: true}),
        o),
       "can contract sealed object");

    raises(function() { guard(
        object({ x: Num }, {sealed: true}),
        {x:3});
    }, "object is not sealed");

    ok(guard(
        object({ x: Num }, {sealed: false}),
        {x:3}),
       "object is not sealed");

    raises(function() { guard(
        object({ x: Num }, {sealed: false}),
        o);
    }, "object is sealed");

    o = Object.freeze({x:3});
    ok(guard(
        object({ x: Num }, {frozen: true}),
        o),
       "can contract frozen object");

    raises(function() { guard(
        object({ x: Num }, {frozen: true}),
        {x:3});
    }, "object is not frozen");

    ok(guard(
        object({ x: Num }, {frozen: false}),
        {x:3}),
       "object is not frozen");

    raises(function() { guard(
        object({ x: Num }, {frozen: false}),
        o)
    }, "object is frozen");

    var fr = guard(
        object({ x: Num }, {frozen: true}),
        o);

    same(fr.x, 3, "can read frozen object");
    raises(function() { Object.defineProperty(fr, "y", {value: 42}); }, "adding property to frozen obj");
    raises(function() { fr.x = 55;}, "writing to frozen object");
    raises(function() { delete fr.x;}, "deleting from frozen object");

    raises(function() { guard(
        object({ x: Num }, {extesible: false}),
        {})
    }, "object is not extensible");
    var noex = guard(
        object({ x: Num }, {extesible: false}),
        Object.preventExtensions(o));
    raises(function() { noex.foo = 42; }, "can't set new property on non-extensible object");
});

test("object with optional properties", function() {
    raises(function() { guard(
        object({ a: opt(Num), b: Str }),
        {a: 42});
    }, "missing required property");
    ok(guard(
        object({ a: opt(Num), b: Str }),
        {b: "foo"}),
       "missing optional property");

});

test("property descriptors on an object's properties", function() {
    var o = {};
    Object.defineProperty(o, "a", { value: 42, writable: false });
    Object.defineProperty(o, "b", { value: "foo", writable: true });
    Object.defineProperty(o, "c", { value: true, configurable: false });
    Object.defineProperty(o, "d", { value: 42, enumerable: false });
    ok(guard(
        object({
            a: {value: Num, writable: false},
            b: {value: Str, writable: true},
            c: {value: opt(Bool), configurable: false},
            d: {value: Num, enumerable: false}
        }),
        o),
       "all prop descriptors match the contract");
    o = {};
    Object.defineProperty(o, "a", { value: 42, writable: true });
    Object.defineProperty(o, "b", { value: "foo", writable: false });
    Object.defineProperty(o, "c", { value: true, configurable: true });
    Object.defineProperty(o, "d", { value: 42, enumerable: true });
    raises(function() { guard(
        object({
            a: {value: Num, writable: false},
            b: {value: Str, writable: true},
            c: {value: opt(Bool), configurable: false},
            d: {value: Num, enumerable: false}
        }),
        o);
    }, "all prop descriptors match the contract");
});

test("recursive object", function() {
    var o = {a: 42, b: null, c: function(x) { return {a: "foo"}; }, d: {z: "bar", s: null}};
    o.b = o;
    o.d.s = o.d;

    o = guard(
        object({
            a: Num,
            b: Self,
            c: fun(Num, Self),
            d: object({
                z: Str,
                s: Self
            })
        }),
        o);

    same(o.a, 42, "abides by contract");
    same(o.b.a, 42, "abides by contract");
    raises(function() { o.b.a = "foo"; }, "violates contract");

    raises(function() { o.c("foo"); }, "violates contract");
    raises(function() { o.c(42).a; }, "server violates contract");
    same(o.d.z, "bar", "abides by contract");
    raises(function() { o.d.s.z = 42; }, "violates contract");

});

test("objects with pre/post conditions", function() {
    var withPre = {x: 0, dec: function() { return --this.x; }};
    ok(withPre.dec() === -1, "works before contract");
    var withPreC = guard(
        object({
            x: Num,
            dec: fun(any, Num, {
                pre: function(obj) {
                    return obj.x > 0;
                },
                post: function(obj) {
                    return obj.x > 0;
                }
            })
        }),
        withPre);
    raises(function() { withPreC.dec(); }, "doesn't pass precondition");
    withPreC.x = 1;
    raises(function() { withPreC.dec(); }, "doesn't pass postcondition");
});

test("checking prototypes", function() {
    var A = {
        a: function() { return "foo"; },
        b: 42
    };
    equals(A.a(), "foo");
    equals(A.b, 42);

    var AC = guard(object({a: fun(any, Str), b: Num}), A);
    equals(AC.a(), "foo");
    equals(AC.b, 42);
    raises(function() { AC.b = "42"; }, "contract doesn't allow a string to flow to b");
    equals(AC.b, 42, "b was not changed in previous test");

    var ABadC = guard(object({a: fun(any, Num), b: Str}), A);
    raises(function() { ABadC.a(); }, "contract says number but function give string");
    raises(function() { ABadC.b; }, "contract doesn't match value stored in b");

    var B = Object.create(A);
    equals(B.a(), "foo");
    equals(B.b, 42);

    var BC = Object.create(AC);
    equals(BC.a(), "foo");
    equals(BC.b, 42);
    ok(BC.b = "foo", "since b is assigned to BC not proto there is not contract to stop it");
    equals(BC.b, "foo");

    var BBadC = Object.create(ABadC);
    raises(function() { BBadC.a(); }, "contract on prototype says number but gives string");
    raises(function() { BBadC.b; }, "contract on proto still doesn't match value stored in b");

    var BGoodAttemptC = guard(
        object({a: fun(any, Str), b: Num}),
        BBadC);
    raises(function() { BGoodAttemptC.a(); }, "contract on prototype still says there is a problem");
    BBadC.a = function() { return "bar"; };
    equals(BBadC.a(), "bar", "ok now we are shadowning bad contract");

    var B_has_C_not_A = guard(object({a: fun(any, Str), b: Str}),
                                Object.create(A));
    raises(function() { B_has_C_not_A.b; }, "blame even though contract is on object but prop is on proto");
});


test("basic arrays", function() {
    var ar = guard(
        arr([Str, Bool]),
        ["foo", false]);
    same(ar[0], "foo", "tupel form of array");
    same(ar[1], false, "tupel form of array");
    ar = guard(
        arr([Str, Bool]),
        [false, "foo", 42]);
    raises(function() { ar[0]; }, "brakes tuple form");
    raises(function() { ar[1]; }, "brakes tuple form");
    ok(ar[2], "not covered by contract");
    ar = guard(
        arr([___(Bool)]),
        [true, "foo", true, false, true]);
    ok(ar[2], "arbitrary number of bools ___(Bool)");
    ok(ar[4], "arbitrary number of bools ___(Bool)");
    raises(function() { ar[1]; }, "element doesn't match ___(Bool) contract");
    raises(function() { ar[0] = "foo"; }, "element doesn't match ___(Bool) contract");

    ar = guard(
        arr([Str, Num, ___(Bool)]),
        [false, 42, true, false, true]);
    ok(ar[1], "arbitrary number of bools ___(Bool)");
    ok(ar[4], "arbitrary number of bools ___(Bool)");
    raises(function() { ar[0]; }, "element doesn't match ___(Bool) contract");

    ar = guard(
        arr([Str]),
        ["foo"]);
    ok(Array.isArray(ar), "Array.isArray should still work with proxied arrays");
});

module("temporal contracts");

test("basic temporal contracts", function() {
    var on = [true],
        NumC = check(function(x, stack) {
            if(stack[0][0]) { return typeof x === 'number'; }
            else { return false; }
        });
    var incC = guard(
        fun([NumC], NumC, {checkStack: function(stack) { return stack[0][0]; }}),
        function(x) { return x + 1; },
        false,
        function(stack) { stack.push(on); });

    same(incC(42), 43, "works when membrane is on");
    on[0] = false;
    raises(function() { incC(42); }, "membrane is off so fails");
});

test("temporal contracts can do dependency", function() {
    var NumArg = check(function(x, stack) {
            stack.push(x);
            return typeof x === 'number';
        }),
        NumRng = check(function(x, stack) {
            var arg = stack.pop();
            return (typeof x === 'number') && (x > arg);
        }),
        incC = guard(
            fun([NumArg], NumRng),
            function(x) { return x + 1; }),
        incBadC = guard(
            fun([NumArg], NumRng),
            function(x) { return x - 1; });

    same(incC(42), 43, "abides by contract");
    raises(function() { incBadC(42); }, "violates contract");
});


test("a basic temporal contract forbidding calling after return", function() {
    var stolen_ref,
        apply = guard(
        fun([fun(any, Bool, {checkStack: function(stack) {
            return stack.pop();
        }}), any],
            check(function(x, stack) {
                stack.pop(); stack.push(false);
                return typeof x === 'boolean';
            })),
        function(cmp, x) { stolen_ref = cmp; return cmp(x); },
        false,
        function(stack) { stack.push(true); });

    same(apply(function(x) { return x > 0; }, 42), true);
    raises(function() { stolen_ref(42); }, "attempted to call function after return");
});

test("can disable contract checking", function() {
    contracts.enabled(false);
    var id = guard(
        fun(Num, Num),
        function(x) { return x; }
    );
    same(id("foo"), "foo", "violates contract but ok since they are disabled");
    contracts.enabled(true);
    id = guard(
        fun(Num, Num),
        function(x) { return x; }
    );
    raises(function() { id("foo"); }, "violates contract and now raises blame");
});

test("contract equality", function() {
    var c1 = fun(Num, Num),
        c2 = fun(Num, Num),
        o1 = object({a: Num}),
        o2 = object({a: Num});


    ok(c1.equals(c1), "function is eq to itself");
    ok(c1.equals(c2), "same fun contracts");

    c1 = fun(Num, Num);
    c2 = fun(Str, Num);
    ok(!c1.equals(c2), "different fun contracts");
    c1 = fun(Num, Num);
    c2 = fun(Num, Str);
    ok(!c1.equals(c2), "different fun contracts");
    c1 = fun(Num, Num, {callOnly: true} );
    c2 = fun(Num, Num, {callOnly: true} );
    ok(c1.equals(c2), "same fun contracts with opts");
    c1 = fun(Num, Num, {callOnly: true} );
    c2 = fun(Num, Num, {callOnly: false} );
    ok(!c1.equals(c2), "differnt fun contracts with opts");
    c1 = fun(Num, Num, {callOnly: false} );
    c2 = fun(Num, Num, {callOnly: false, newOnly: true} );
    ok(!c1.equals(c2), "differnt fun contracts with different opts");
    c1 = fun([Str, Num], Num, {callOnly: true} );
    c2 = fun([Str, Num], Num, {callOnly: true} );
    ok(c1.equals(c2), "same fun contracts with opts and multi args");
    c1 = fun([Str, Num], Num, {callOnly: true} );
    c2 = fun([Num, Num], Num, {callOnly: true} );
    ok(!c1.equals(c2), "different fun contracts with opts and multi args");
    c1 = fun(Num, Num, {this: object({name: Str})} );
    c2 = fun(Num, Num, {this: object({name: Str})} );
    ok(c1.equals(c2), "same fun contracts with this contract");
    c1 = fun(Num, Num, {this: object({name: Str})} );
    c2 = fun(Num, Num, {this: object({name: Num})} );
    ok(!c1.equals(c2), "same fun contracts with this contract");

    o1 = object({a: Num});
    o2 = object({a: Num});
    ok(o1.equals(o2), "same objects");
    o1 = object({a: Num});
    o2 = object({a: Str});
    ok(!o1.equals(o2), "different objects");
    o1 = object({a: Num, f: fun(Num, Num)});
    o2 = object({a: Num, f: fun(Num, Num)});
    ok(o1.equals(o2), "same objects funtion props");
    o1 = object({a: Num, f: fun(Num, Num)});
    o2 = object({a: Num, f: fun(Num, Str)});
    ok(!o1.equals(o2), "different objects funtion props");
    o1 = object({a: Num});
    o2 = object({a: Num, f: fun(Num, Num)});
    ok(!o1.equals(o2), "different objects missing function props");

    ok(!c1.equals(o1), "different contracts completely");
});

test("exports object", function() {
    var id, myid, exports, require;
    exports = contracts.exports("id_provider");

    id = guard(
        fun(Num, Num),
        function(x) { return x; }
    );

    exports.id = id;

    myid = contracts.use(exports, "id_consumer");
    // should blame id_consumer
    raises(function() { myid.id("foo"); });
});

test("instanceof works with contracts", function() {
    function Foo() {
        this.name = "foo";
    }
    function Bar() {
        this.name = "bar";
    }

    var f = new Foo();

    var ftrue = guard(
        fun(object({name: Str}), Bool),
        function(o) {
            return o instanceof Foo;
        });
    var ffalse = guard(
        fun(object({name: Str}), Bool),
        function(o) {
            return o instanceof Bar;
        });

    ok(ftrue(f), "instance of Foo");
    ok(!ffalse(f), "not an instance of Bar");
});

module("object extends");

test("extends works with object contracts", function(){
   var o1 = object({silent: Bool});
   var o2 = object({optional: Bool});

   var newContract = extend(o1,o2);
   ok(guard(newContract,{silent: true, optional: false}));
   raises(function(){guard(newContract,{silent:true})});

   var o3 = object({silent: Str});
   var o4 = object({silent: Bool});
   raises(function(){extend(o1,o3)});
   ok(extend(o1,o4));

    o1 = object({silent: Bool});
    var f = fun(Num,Num);

    raises(function(){extend(o1,{})});
    raises(function(){extend({},o1)});
    raises(function(){extend(o1,f)});
    raises(function(){extend(f,o1)});
});


module("Blame for too many arguments");
test("", function() {
    var id = function(x){return 2;};
    var f = guard(fun([Num],Num), id);
    var f2 = guard(fun([opt(Num)], Num), id);
    raises(function(){ f(2,3)});
    ok(f(2));
    ok(f2(2));
    ok(f2());
    raises(function() { f2(2,3)});
});

module("Rest contract for functions");
test("", function() {
   var id = function(x){return 2;};
   var f = guard(fun([Num],Num, {rest: Str}), id);
   var g= guard(fun([Num],Num), id);
   raises(function() { g(2,"hi")});
   ok(f(2));
   ok(f(2, "foo"));
   ok(f(2, "foo", "foo", "foo", "foo"));
   raises(function() { f(2, true)});
   raises(function() { f(2,2);});
   raises(function() { f(2, "foo", "foo", 3, "foo")});

    var h = guard(fun([opt(Num)], Num, {rest: Str}), id);
    ok(h(2));
    ok(h(2,"ho"));
    raises(function() { h(true)});
    ok(h("ho"));
    ok(h("hi","ho", "ho"));
});

module("Object class contract");
test("", function() {

    var Foo = function(){};
    Foo.prototype.hi = "ho";

    var f = guard(object({}, {"class": object({ hi: Str},{})}), Foo);
    var o = new f();
    ok(o.hi, "should not raise on hi");

    var h = guard(object({}, {"class": object({ hi: Num},{})}), Foo);
    raises(function(){ var o = new h(); console.log(o.hi);});

    var Bar = function() { this.cid = "ho";};
    var g = guard(object({}, {"class": object({ cid: Str},{})}), Bar);

    o = new g();
    ok(o.cid, "cid should not raise");

    var k = guard(object({}, {"class": object({ cid: Str},{})}), Foo);
    raises(function(){ var o = new k();});
});

test("test coffeescript class inheritance", function() {
    var A, B,
        __hasProp = {}.hasOwnProperty,
        __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

    A = (function() {
        function A() {}

        A.prototype.foo = function() {
            return "hi";
        };

        return A;

    })();

    B = (function(_super) {
        __extends(B, _super);

        function B() {
            return B.__super__.constructor.apply(this, arguments);
        }

        return B;

    })(A);

    var f = guard(object({},{"class": object({foo: fun([], Str)}, {})}), B);
    var g = guard(object({},{"class": object({foo: fun([], Num)}, {})}), B);
    var o = new f();
    ok(o.foo(), "should pass since it expects and return a string");
    raises(function(){ var o = new g(); f.foo();}, "should raise since it returns string but expects num");
});

module("Overloaded contracts");

test("basic overloaded function contracts", function(){
    var c1 = fun([Str], Num);
    var c2 = fun([Num], Str);

    var ov = overload_fun(c1, c2);

    var f = function() { return "foo";};
    var g = function(){ return 2;};
    var f2 = guard(ov, f);
    var g2 = guard(ov, g);

    raises(function(){f2("ho")}, "should not be ok, we have Str->Num that should match but returns Str");
    ok(f2(2), "should be ok since Num-> Str");
    ok(g2("foo"), "Str->Num g returns Num so ok");
    raises(function(){g2(2)}, "Num-Str not ok since expects Str");

    var k1 = fun([Str, Num], Num);
    var k2 = fun([Str, Str], Num);
    var oc = overload_fun(k1, k2);

    var h = function() {return 2};
    var hc = guard(oc, h);

    ok(hc("foo", 2), "Str,Num->Num call with 2 arguments ok");
    ok(hc("foo", "bar"), "Str,Str->Num call with 2 arguments ok");
    raises(function(){ hc("foo", false)}, "called with wrong second argument");
    raises(function(){ hc(2);}, "called with too few arguments");


});

test("basic overloaded function contracts with optional arguments", function(){
    var c1 = fun([Str, opt(Num)], Num);
    var c2 = fun([Str, opt(Str)], Num);
    var oc = overload_fun(c1, c2);

    var f = function(){return 2;};
    var fc = guard(oc, f);

    ok(fc("hi"), "passes with correct first argument");
    ok(fc("hi",2), "passes with correct second optional argument Num");
    ok(fc("hi","ho"), "passes with correct second optional argument Str");
    raises(function(){fc("hi",false)}, "should fail with wrong optional argument Bool (should be either Str or Num)");
    raises(function(){fc(false)}, "should fail with wrong nonoptional argument");
});

test("higher order overloaded contracts", function(){

    var c1 = fun([fun([Str],Num)], Any);
    var c2 = fun([fun([Num],Str)], Any);
    var oc = overload_fun(c1, c2);

    var f = function(h) { h(true)};
    var givesNum = function() { return 42;};
    var givesStr = function(){ return "foo"};
    var id = function (x) { return x};
    var g = function(h) { return h("foobar")};
    var h = function(h) { return h(2);};

    var f1 = guard(oc, f);
    var f2 = guard(oc, g);
    var f3 = guard(oc, h);

    //f1(id);
    raises(function(){f1(id);});
    raises(function(){f2(givesStr)});
    ok(f2(givesNum));
    ok(f3(givesStr));
    raises(function(){ f3(givesNum) });

    var c3 = fun([Any], fun([Str],Str));
    var c4 = fun([Any], fun([Num], Str));
    var oc2 = overload_fun(c3, c4);

    var j = guard(oc2,function(){ return givesNum;});
    raises(function() {j()(2); });
    raises(function() {j()(true)});
    var k = guard(oc2, function(){ return givesStr});
    ok(k()(2));
    ok(k()("hi"));
    raises(function() {k()(true)});
});

test("object contracts in overloaded contracts", function(){
    var c1 = fun([object({"foo": Str})], Any);
    var c2 = fun([object({"bar": Str})], Any);
    var oc = overload_fun(c1, c2);

    var f = function(o){ return o.foo; };
    var f1 = guard(oc, f);
    var g = function(o) { return o.bar; };
    var g1 = guard(oc, g);

    raises(function(){ f1({"foo": 2});}, "should fail since prop foo is Num not Str");
    ok(f1({"foo": "hi"}), "should be ok since prop foo is Str expected Str");
    raises(function(){ g1({"bar": 2})});
    ok(g1({"bar": "foo"}));
});

module("object silent mode");

test("test object contract silent mode", function(){
    // we allow missing on creation, then it's turned into an optional contract
    var c = object({"foo": Str}, {silent: true});
    var c2 = object({"foo": Str});
    ok(guard(c, {}));
    raises(function(){ guard(c2, {})});
    var f = guard(c, {});
    ok(f.foo = "hi");
    raises(function() {f.foo = 3; });

});