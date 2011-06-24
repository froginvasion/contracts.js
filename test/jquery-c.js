/*global jQuery: true, Contracts: true */

// add contracts to jQuery
// jQuery.myVerySpecialProperty = "hi";
// jQuery = Contracts.C.guard(
//     Contracts.C.object({
//         myVerySpecialProperty: Contracts.K.Number
//     }), jQuery, "server", "client");

jQuery = (function() {
    var C = Contracts.C,
        K = Contracts.K,
        jQueryContract = C.object({
            length : K.String
        });

    return C.guard(
        C.and(
            C.fun(C.or(K.String, K.Array), jQueryContract),
            jQueryContract
        ),
        jQuery,
        "server",
        "client");
})();
