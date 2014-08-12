require('harmony-reflect');

var __extends = this.__extends || function (d, b) {
    for (var p in b) if (b.hasOwnProperty(p)) d[p] = b[p];
    function __() { this.constructor = d; }
    __.prototype = b.prototype;
    d.prototype = new __();
};

var handler = {"get": function (receiver, name) {
        if (receiver.hasOwnProperty(name)) {
            return Proxy(receiver[name], {});
        }
    return receiver[name];
    }
};



var Dog = (function () {
    function Dog() {
    }
    Dog.prototype.bark = function () {
    };
    return Dog;
})();

var ProxyDog;

ProxyDog = Proxy(Dog, {});
ProxyDog.prototype = Proxy(Dog.prototype, {});

ProxyDog = Proxy(Dog, handler);

var Puppy = (function (_super) {
    __extends(Puppy, _super);

    function Puppy() {
        _super.apply(this, arguments);
    }

    return Puppy;
})(ProxyDog);


var instance = new ProxyDog();
console.log(instance instanceof Dog);//true

instance = new Puppy();
console.log(instance instanceof Dog);//false