require('harmony-reflect');
var c = require('./../lib/contracts');
c.autoload();

var __extends = this.__extends || function (d, b) {
    for (var p in b) if (b.hasOwnProperty(p)) d[p] = b[p];
    function __() { this.constructor = d; }
    __.prototype = b.prototype;
    var proto = b.prototype;
    console.log("is b.prototype === Foo.prototype?");
    console.log(proto === Foo.prototype);
    console.log("is b.prototype === FooProxy.prototype?");
    console.log(proto === FooProxy.prototype);
    console.log(proto.constructor);
    console.log(proto);
    d.prototype = new __();
};

var Foo = (function () {
    function Foo() {
    }
    Foo.prototype.swing = function() {
        console.log("I'mswingingbro");
    };
    return Foo;
})();

var FooProxy;
FooProxy = guard(object({}, {"class": object({},{})}), Foo);

FooProxy = Proxy(Foo, {});
FooProxy.prototype = Proxy(Foo.prototype, {});

FooProxy = Proxy(Foo, {"get": function(rec, name) {
    if(rec.hasOwnProperty(name)) {
        var p = Proxy(rec[name], {});
        console.log("getting prototype...");
        console.log(p === Foo.prototype);
        return p;
    }
    return rec[name];
}});

var Bar = (function (_super) {
    __extends(Bar, _super);
    function Bar() {
        _super.apply(this, arguments);
    }
    Bar.prototype.throw_axe = function() { console.log("I'm throwing an axe!")};
    return Bar;
})(FooProxy);

var bf = Bar.bind.apply(Bar, [{}]);
var i = new bf();

var applyOnInstance = function(o, f) {
    f(o);
    var new_proto = Object.getPrototypeOf(o);
    if (new_proto !== null) {
        applyOnInstance(new_proto, f);
    } else {
        console.log(new_proto);
    }
};

applyOnInstance(i, function(o) {
    console.log(o);
    console.log(o === Foo.prototype);
});


console.log("i instanceof Foo");
console.log(i instanceof Foo);

