"use strict"

###
contracts.coffee
http://disnetdev.com/contracts.coffee

Copyright 2011, Tim Disney
Released under the MIT License
###
root = {}

enabled = if Proxy? then true else false

show_parent_contracts = true

# contract_orig_map ::
#   set: (Any, OrigMap) -> Undefined
#   get: (Any) -> OrigMap
contract_orig_map = if WeakMap? then new WeakMap() else {}

class Unproxy
  constructor: ->
    if WeakMap?
      @hasWeak = yes
      @unproxy = new WeakMap()
    else
      @hasWeak = no
      @unproxy = []

  set: (p, c) ->
    if @hasWeak
      @unproxy.set p, c
    else
      @unproxy.push
        proxy: p
        contract: c

  get: (p) ->
    if @hasWeak
      if (p isnt null) and typeof p is "object" or typeof p is "function"
        @unproxy.get p
      else
        undefined
    else
      pc = @unproxy.filter (el) ->
        p is el.proxy
      throw "assumption failed: unproxy object stores multiple unique proxies"  if pc.length > 1
      if pc.length is 1
        pc[0]
      else
        undefined

unproxy = new Unproxy()

Utils =
  # walk the proto chain to get the property descriptor
  getPropertyDescriptor: (obj, prop) ->
    o = obj
    while o isnt null
      desc = Object.getOwnPropertyDescriptor(o, prop)
      return desc  if desc isnt `undefined`
      o = Object.getPrototypeOf(o)
    undefined



  # merges props of o2 into o1 return o1
  merge: (o1, o2) ->
    o3 = {}
    f = (o) ->
      for name of o
        o3[name] = o[name]  if o.hasOwnProperty(name)

    f o1
    f o2
    o3

  hasNoHoles: (obj) ->
    i = 0
    while i < obj.length
      return false  unless i of obj
      i++
    true

  # if a1 and a2 are differently sized, return the empty list
  zip: (a1, a2) ->
    ret = []
    if not Array.isArray(a1) or not Array.isArray(a2) or (a1.length isnt a2.length)
      ret = []
    else
      i = 0
      while i < a1.length
        ret.push [ a1[i], a2[i] ]
        i++
    ret


checkOptions = (a, b) ->
  pOpt = true
  for name of a
    if a[name] instanceof Contract
      pOpt = false unless (b[name] instanceof Contract) and (a[name].equals b[name])
    else pOpt = false  if a[name] isnt b[name]
  for name of b
    pOpt = false  unless name of a
  pOpt

# Parses out filename and line number. Expects an array where the 0th entry
# is the file location and line number
# [...Str] -> [Str, Num] or null
findCallsite = (trace) ->
  t = trace[0]
  # string looks like {adsf}@file:///path/to/file.js:42
  re = /@(.*):(\d*)$/
  match = re.exec(t)
  if match
    [ match[1], parseInt(match[2], 10) ]
  else
    null

# (ModuleName, ModuleName, Str, [Contract]) -> \bot
_blame = (toblame, other, msg, parents) ->
  ps = parents.slice(0)
  server = (if toblame.isServer then toblame else other)
  m = "Contract violation: " + msg + "\n" +
      "Value guarded in: " + server + " -- blame is on: " + toblame + "\n"

  m += "Parent contracts:\n" + ps.reverse().join("\n")  if ps and show_parent_contracts

  err = new Error(m)
  st = printStackTrace(e: err)
  err.cleaned_stacktrace = st

  # pretend the error was thrown at the place in usercode where the violation occured
  callsite = findCallsite(st)
  if callsite
    # by setting these fields tools like firebug will link to the
    # appropriate place in the user code
    err.fileName = callsite[0]
    err.lineNumber = callsite[1]
  throw err

# (ModuleName, ModuleName, Contract, any, [Contract]) -> \bot
blame = (toblame, other, contract, value, parents) ->
  cname = contract.cname or contract
  msg = "expected <" + cname + ">" +
        ", actual: " + (if typeof (value) is "string" then "\"" + value + "\"" else value)

  throw _blame(toblame, other, msg, parents)

blameM = (toblame, other, msg, parents) -> _blame toblame, other, msg, parents

# creates an identity proxy handler
idHandler = (obj) ->
  getOwnPropertyDescriptor: (name) ->
    desc = Object.getOwnPropertyDescriptor(obj, name)
    desc.configurable = true  if desc isnt undefined
    desc

  getPropertyDescriptor: (name) ->
    desc = Utils.getPropertyDescriptor(obj, name)
    desc.configurable = true  if desc
    desc

  getOwnPropertyNames: ->
    Object.getOwnPropertyNames obj

  getPropertyNames: ->
    Object.getPropertyNames obj

  defineProperty: (name, desc) ->
    Object.defineProperty obj, name, desc

  'delete': (name) ->
    delete obj[name]

  fix: ->
    if Object.isFrozen(obj)
      return Object.getOwnPropertyNames(obj).map((name) ->
        Object.getOwnPropertyDescriptor obj, name
      )
    undefined

  has: (name) ->
    name of obj

  hasOwn: (name) ->
    Object::hasOwnProperty.call obj, name

  enumerate: ->
    result = []
    name = undefined
    for name of obj
      result.push name
    result

  get: (receiver, name) ->
    obj[name]

  set: (receiver, name, val) ->
    obj[name] = val
    true
  keys: ->
    Object.keys obj


class Contract
  constructor: (@cname, @ctype, @handler) ->
    @parent = null

  check: (val, pos, neg, parentKs, stack) ->
    c = unproxy.get val
    if c and c.equals @
      # don't bother wrapping twice though we want to run the handler
      # for the initialization check that happens and just ignore the return
      @handler val, pos, neg, parentKs, stack
      val
    else
      @handler val, pos, neg, parentKs, stack

  toContract: -> @
  toString: -> @cname
  equals: (other) -> throw new Error "Equality checking must be overridden"

class ModuleName
  constructor: (@filename, @linenum, @isServer) ->
  toString: -> @filename + (if @linenum is "" then "" else (":" + @linenum))

Function::toContract = ->
  name = "<user defined: " + @toString() + ">"
  check this, name

# create a flat (predicate) contract
check = (p, name) ->
  c = new Contract name, "check", (val, pos, neg, parentKs, stack) ->
    if p(val, stack)
      val
    else
      blame pos, neg, this, val, parentKs

  c.equals = (other) ->
    (@cname is other.cname) and (@handler is other.handler)
  c

# create a function contract
fun = (dom, rng, options) ->
  cleanDom = (dom) ->
    # wrap the domain in array so we can be consistent
    dom = [ dom ]  if not Array.isArray dom
    # make sure all of the arguments are contracts
    if (dom.some (d) -> not (d instanceof Contract))
      throw new Error "domain argument to the function contract is not a contract"
    # don't allow required argument contracts to follow optional
    dom.reduce ((prevWasOpt, curr) ->
      if curr.ctype is "opt"
        true
      else
        if prevWasOpt
          throw new Error "A required domain contract (#{curr}) followed an " +
            "optional domain contract in a function contract"
        else
          false
    ), false
    dom

  # dom is overloaded so check if was called as
  # an object with the contracts for call/new
  if dom and dom.call and dom["new"]
    # different rng/dom for call/new
    calldom = cleanDom(dom.call[0])
    callrng = dom.call[1]
    newdom = cleanDom(dom["new"][0])
    newrng = dom["new"][1]
    options = rng or {}
  else
    # rng/dom for call/new are the same
    calldom = cleanDom dom
    callrng = rng
    newdom = calldom
    newrng = callrng
    options = options or {}

  callOnly = options and options.callOnly
  newOnly = options and options.newOnly

  throw new Error "Cannot have a function be both newOnly and newSafe"  if callOnly and newOnly
  throw new Error "Illegal arguments: cannot have both newOnly and a contract on 'this'"  if newOnly and options["this"]

  domName = "(" + calldom.join(",") + ")"
  optionsName = (if options["this"] then "{this: " + options["this"].cname + "}" else "")
  contractName = domName + " -> " + callrng.cname + " " + optionsName

  c = new Contract(contractName, "fun", (f, pos, neg, parentKs, stack) ->
    handler = idHandler f
    that = this
    parents = parentKs.slice(0)
    blame pos, neg, this, f, parents  if typeof f isnt "function"

    parents.push that

    ###
    options:
      isNew: Bool   - make a constructor handler (to be called with new)
      newSafe: Bool - make call handler that adds a call to new
      pre: ({} -> Bool) - function to check preconditions
      post: ({} -> Bool) - function to check postconditions
      this: {...} - object contract to check 'this'
      rest: Contract - this contract will be checked for all remaining arguments
    ###
    makeHandler = (dom, rng, options) ->
      functionHandler = ->
        args = []

        if options and options.checkStack and not (options.checkStack(stack))
          throw new Error("stack checking failed")

        if typeof options.pre is "function" and not options.pre this
          # check pre condition
          blame neg, pos,
            "precondition: " + options.pre.toString(),
            "[failed precondition]", parents

        if options.rest? and not options.rest instanceof Contract
          blame neg, pos,
            "The rest contract that was supplied isn't a contract"
        #rest contracts are always supposed to be optional!
        if options.rest?.ctype is not "opt"
          options.rest = root.opt(options.rest)


        # check all the arguments
        i = 0
        max_i = Math.max dom?.length, arguments.length
        if typeof dom?.length is 'number'
          blameM neg, pos, "Too many arguments supplied to function", parents  if arguments.length > dom.length and not options.rest

        isrest = null
        while i < max_i
          # might pass through undefined which is fine (opt will take
          # care of it if the argument is actually optional)
          #
          # blame is reversed
          if isrest
            checked = options.rest.check arguments[i], neg, pos, parents, stack
          else
            if dom[i]?.ctype is "opt" and arguments[i] isnt undefined and options.rest?
              try
                checked = dom[i].check arguments[i], neg, pos, parents, stack
              catch e
                isrest = true
                checked = options.rest.check arguments[i], neg, pos, parents, stack
            else if not dom[i] and options.rest?
              isrest = true
              checked = options.rest.check arguments[i], neg, pos, parents, stack
            else
              checked = if dom[i]
                dom[i].check arguments[i], neg, pos, parents, stack
              else arguments[i]
          if i < arguments.length
            args[i] = checked
            # assigning back to args since we might be wrapping functions/objects
            # in delayed contracts
          i++

        if typeof rng is "function"
          # send the arguments to the dependent range
          dep_args = if Array.isArray args then args else [args]
          clean_rng = rng.call(this, args)
          if not (clean_rng instanceof Contract)
            throw new Error "range argument to function contract is not a contract"
        else
          clean_rng = rng
          if not (clean_rng instanceof Contract)
            throw new Error "range argument to function contract is not a contract"

        # apply the function and check its result
        if options.isNew or options.newSafe
          # null is in the 'this' argument position for bind...
          # bind will ignore the supplied 'this' when we call it with new
          boundArgs = [].concat.apply([ null ], args)
          bf = f.bind.apply(f, boundArgs)
          res = new bf()
          res = clean_rng.check(res, pos, neg, parents, stack)
        else
          if options.this
            # blame is reversed
            thisc = options.this.check(this, neg, pos, parents, stack)
          else
            thisc = this
          res = clean_rng.check(f.apply(thisc, args), pos, neg, parents, stack)

        # check post condition
        if typeof options.post is "function" and not options.post this
          blame neg, pos,
            "failed postcondition: " + options.post.toString(),
            "[failed postcondition]", parents
        res

    if newOnly
      options.isNew = true
      callHandler = -> blameM neg, pos, "called newOnly function without new", parents
      newHandler = makeHandler(@newdom, @newrng, options)
    else if callOnly
      options.isNew = false
      newHandler = -> blameM neg, pos, "called callOnly function with a new", parents
      callHandler = makeHandler(@calldom, @callrng, options)
    else # both false...both true is a contract construction-time error and handled earlier
      callHandler = makeHandler(@calldom, @callrng, options)
      newHandler = makeHandler(@newdom, @newrng, options)

    p = Proxy.createFunction(handler, callHandler, newHandler)
    unproxy.set p, this
    p
  )
  c.calldom = calldom
  c.callrng = callrng
  c.newdom = newdom
  c.newrng = newrng
  c.raw_options = options
  c.equals = (other) ->
    # can can short circuit here if we're not testing against another contract
    return false  if not other instanceof Contract or other.ctype isnt @ctype

    zipCDom = Utils.zip(@calldom, other.calldom)
    zipNDom = Utils.zip(@newdom, other.newdom)

    pCDom = (zipCDom.length isnt 0) and zipCDom.every (zd) -> zd[0].equals zd[1]
    pNDom = (zipNDom.length isnt 0) and zipNDom.every (zd) -> zd[0].equals zd[1]

    # this will "fail" equality testing if the options object has
    # pre/post functions that are the "same" but not the same reference
    pOpt = checkOptions(@raw_options, other.raw_options)

    pOpt and pCDom and pNDom and (@callrng.equals(other.callrng)) and (@newrng.equals(other.newrng))
  c


overload_fun = (contractParents, blameparents)->
  args = Array::slice.call arguments
  funs = []
  cname = "overloaded contract: "
  i = 0
  if Array.isArray contractParents
    args = Array::slice.call args, 1, args.length
  else
    contractParents = null
  if typeof blameparents is "function"
    args = Array::slice.call args, 1, args.length
  else
    blameparents = null

  while i < args.length
    c = args[i]
    throw new Error "#{c} is not a function contract" if not (c instanceof Contract and (c.ctype is "fun" or c.ctype is "object"))
    funs.push args[i]
    i++

  for f in funs
    cname += f.cname

  getCalldom = (i)->
    res = []
    for f in @
      res.push {"contract": f.calldom[i], "parent": f}
    res

  getCallrng = ->
    res = []
    for f in @
      res.push {"contract": f.callrng, "parent": f}
    res

  isFun = (k)->
    return true if k.ctype is "fun"
    return true if k.ctype is "opt" and k.k.ctype is "fun"
    false

  isCheck = (k)->
    return true if k.ctype is "check"
    return true if k.ctype is "opt" and k.k.ctype is "check"
    false

  isObject = (k)->
    return true if k.ctype is "object"
    return true if k.ctype is "opt" and k.k.ctype is "object"
    false

  isDelayedContract = (k)->
    return true if isFun(k) or isObject(k)
    false


  blameOrThrow = (fns, k, c, pos, neg, errors, parents)->
    if fns.length is 0
      if contractParents?
        cb(k)
      else
        blame pos, neg, c, c.cname, parents

  c = new Contract cname, "overloaded_fun", (f, pos, neg, parentKs, stack)->
    localfuns = funs.slice(0)
    parents = parentKs.slice(0)
    if typeof Proxy is "function"
      handler = {}
    else
      handler = idHandler(f)

    makeHandler = (nondirect)-> (target, thisArg, args)->
      if nondirect
        args = Array::slice.call(arguments)
        target = f
        thisArg = this
      else
        if args is undefined
          args = thisArg
      #reset at each call
      localfuns = funs.slice(0)
      errors = []
      new_arguments = []

      cb = (k)->
        idx = localfuns.indexOf k.parent
        k = localfuns[idx]
        if idx > -1
          localfuns.splice(idx, 1)
        blameOrThrow localfuns, k, c, pos, neg, errors, parents

      i = 0
      #remove all with too many arguments
      max_i = Math.max args.length, Math.max.apply(localfuns.map (f)-> f.calldom.length)
      for func, k in localfuns
        if args.length > func.calldom?.length
          delete localfuns[k]
      localfuns = localfuns.filter (e)-> e

      while i < max_i

        current_arg = args[i]
        delayed_ks = []
        domcontracts = getCalldom.call(localfuns, i)

        for domcontract in domcontracts
          try
            if isDelayedContract domcontract.contract
              delayed_ks.push domcontract.contract
            else
              domcontract.contract.check current_arg, pos, neg, parents, stack
          catch e
            errors.push e
            idx = localfuns.indexOf domcontract.parent
            delete localfuns[idx]
            if contractParents?
              p = contractParents.filter (e)-> e.contract is domcontract.parent
              blameparents(p[0]) if p.length isnt 0


        if delayed_ks.length is 0
          new_arguments[i] = current_arg
        else
          newK = overload_fun.apply(null, [].concat([domcontracts, cb], delayed_ks))
          new_arguments[i] = newK.check current_arg, neg, pos, parents, stack
        i = i + 1

      localfuns = localfuns.filter (e)-> e
      if localfuns.length is 0 and not contractParents?
        blame pos, neg, c, c.cname, parents

      res = target.apply thisArg, new_arguments

      localfuns = localfuns.filter (e)-> e
      if localfuns.length is 0 and not contractParents?
        blame pos, neg, c, c.cname, parents

      delayed_rng = []
      rngcontracts = getCallrng.call(localfuns)
      for rngcontract in rngcontracts
        try
          if isDelayedContract rngcontract.contract
            delayed_rng.push rngcontract.contract
          else
            rngcontract.contract.check res, pos, neg, parents, stack
        catch e
          idx = localfuns.indexOf rngcontract.parent
          delete localfuns[idx]
          if contractParents?
            p = contractParents.filter (e)-> e.contract is rngcontract.parent
            blameparents(p[0]) if p.length isnt 0


      if delayed_rng.length isnt 0
        newK = overload_fun.apply(null, [].concat([rngcontracts, cb], delayed_rng))
        res = newK.check res, pos, neg, parents, stack

      localfuns = localfuns.filter (e)-> e
      if localfuns.length is 0 and not contractParents?
        blame pos, neg, c, c.cname, parents
      res

    handler["apply"] = (target, thisArg, args)->
      makeHandler(false)(target, thisArg, args)

    handler["construct"] = (target, args)->
      makeHandler(false)(target, args)

    handler["defineProperty"] = ->

    handler["delete"] = ->

    handler["get"] = ->

    try
      p = Proxy(f, handler)
    catch e
      p = Proxy.createFunction(handler, makeHandler(true), makeHandler(true))
    unproxy.set p, this
    p

  c.equals = (other)->
    this is other
  c




ctor = (dom, rng, options) ->
  opt = Utils.merge options,
    newOnly: true

  fun dom, rng, opt

ctorSafe = (dom, rng, options) ->
  opt = Utils.merge options,
    newSafe: true

  fun dom, rng, opt



# extend :: (Contract,Contract)-> Contract
extend = (orig,ext)->
  if not (orig instanceof Contract)
    throw new Error "cannot extend non contract"
  if not (ext instanceof Contract)
    throw new Error "cannot extend contract with non contract"
  if orig.oc is undefined
    throw new Error "cannot extend non object contract"
  if ext.oc is undefined
    throw new Error "cannot extend object contract with non object contract"
  origContract = orig.oc
  extendingContract = ext.oc

  for own key, orContract of origContract
    extendedContract = extendingContract[key]
    break if extendedContract is undefined
    if extendedContract["value"] and extendedContract["value"] instanceof Contract
      extendedContract = extendedContract["value"]
    if orContract["value"] and orContract["value"] instanceof Contract
      orContract = orContract["value"]
    if not extendedContract.equals(orContract)
      throw new Error "Both contracts have duplicate properties but contracts are not equal"

  for own key,val of extendingContract
    origContract[key] = val
  c = object(origContract, {})
  c



object = (objContract, options = {}, name) ->
  objName = (obj) ->
    if name is undefined
      props = Object.keys(obj).map (propName) ->
        if obj[propName].cname
          propName + " : " + obj[propName].cname
        else
          propName + " : " + obj[propName].value?.cname
      , this

      "{\n  " + props.join(",\n  ") + "\n}"
    else
      name

  c = new Contract(objName(objContract), "object", (obj, pos, neg, parentKs) ->
    #This test aims to differentiate between V8 in chrome and Gecko in Firefox.
    #Since the direct proxy approach doesn't require default handlers to be implemented, we omit the
    # idhandler in that case. Since in FF Proxy is a function and not in V8, this is how we do it.
    if typeof Proxy isnt "function"
      handler = idHandler obj
    else
      handler = {}
    that = this
    parents = parentKs.slice(0)
    parents.push this

    nonObject = [
      "undefined"
      "boolean"
      "number"
      "string"
    ]
    # proxies only work correctly for objects/functions so we will
    # only accept "real" objects here
    if typeof obj in nonObject
      blame pos, neg, this, obj, parentKs

    if options.extensible is true and not Object.isExtensible(obj)
      blame pos, neg, "[extensible object]", "[non-extensible object]", parents

    if options.extensible is false and Object.isExtensible(obj)
      blame pos, neg, "[non-extensible]", "[extensible object]", parents

    if options.sealed is true and not Object.isSealed(obj)
      blame pos, neg, "[sealed object]", "[non-sealed object]", parents

    if options.sealed is false and Object.isSealed(obj)
      blame pos, neg, "[non-sealed object]", "[sealed object]", parents

    if options.frozen is true and not Object.isFrozen(obj)
      blame pos, neg, "[frozen object]", "[non-frozen object]", parents

    if options.frozen is false and Object.isFrozen(obj)
      blame pos, neg, "[non-frozen object]", "[frozen object]", parents

    if options.class and not options.class instanceof Contract
      _blame pos, neg, "class option isnt a contract", parents

    # do some cleaning of the object contract...
    # in particular wrap all object contract in a prop descriptor like object
    # for symmetry with user defined contract property
    # descriptors: object({ a: Num }) ==> object({ a: {value: Num} })
    for own prop of @oc
      # todo: commenting out for now to allow us to have an object contract prototype chain
      # only reason not too allow this is if the user puts something silly on the chain.
      # if(!this.oc.hasOwnProperty(prop)) {
      #     continue;
      # }
      contractDesc = @oc[prop]
      # this will throw exception if obj is string,num,etc.
      # even though they still might have "properties"
      if (typeof obj is 'object') or (typeof obj is 'function')
        objDesc = Utils.getPropertyDescriptor(obj, prop)
      else if typeof obj[prop] isnt 'undefined'
        objDesc =
          value: obj[prop]
          writable: true
          configurable: true
          enumerable: true
      else
        objDesc = null



      # pull out the contract (might be direct or in a descriptor like {value: Str, writable: true})
      if contractDesc instanceof Contract
        value = contractDesc
      else
        # case when defined as a contract property descriptor
        if contractDesc["value"] and contractDesc["value"] instanceof Contract
          value = contractDesc["value"]
        # something other than a descriptor
        else
          blameM pos, neg, "property #{prop} in the object contract was not a contract", parents

      if objDesc
        if not contractDesc instanceof Contract
          # check the contract descriptors against what is actually on the object
          # and blame where apropriate
          if contractDesc.writable is true and not objDesc.writable
            blame pos, neg, "[writable property: #{prop}]", "[read-only property: #{prop}]", parents

          if contractDesc.writable is false and objDesc.writable
            blame pos, neg, "[read-only property: #{prop}]", "[writable property: #{prop}]", parents

          if contractDesc.configurable is true and not objDesc.configurable
            blame pos, neg, "[configurable property: #{prop}]", "[non-configurable property: #{prop}]", parents

          if contractDesc.configurable is false and objDesc.configurable
            blame pos, neg, "[non-configurable property: #{prop}]", "[configurable property: #{prop}]", parents

          if contractDesc.enumerable is true and not objDesc.enumerable
            blame pos, neg, "[enumerable property: #{prop}]", "[non-enumerable property: #{prop}]", parents

          if contractDesc.enumerable is false and objDesc.enumerabl
            blame pos, neg, "[non-enumerable property: #{prop}]", "[enumerable property: #{prop}]", parents

        # contract descriptors default to the descriptor on the value unless
        # explicitly specified by the contract
        @oc[prop] =
          value: value
          writable: contractDesc.writable or objDesc.writable
          configurable: contractDesc.configurable or objDesc.configurable
          enumerable: contractDesc.enumerable or objDesc.enumerable
      else
        # property does not exist but we have a contract for it
        if value.ctype is "opt"
          # the opt contract allows a property to be optional
          # so just put in the contract with all the prop descriptors set to true
          @oc[prop] =
            value: value
            writable: true
            configurable: true
            enumerable: true
        else
          blame pos, neg, this, "[missing property: #{prop}]", parents

    # check object invariant
    if options.invariant
      invariant = options.invariant.bind(obj)
      blame neg, pos, "invariant: #{options.invariant.toString()}", obj, parents  unless invariant()

    handler.defineProperty = (name, desc) ->
      # note: we coulad have also allowed a TypeError to be thrown by the system
      # if in strict mode or silengtly fail otherwise but we're using the blame system
      # for hopfully better error messaging
      if (options.extensible is false) or options.sealed or options.frozen
        # have to reverse blame since the client is the one calling defineProperty
        blame neg, pos, "[non-extensible object]",
          "[attempted to change property descriptor of: #{name}]", parents

      if not that.oc[name].configurable
        blame neg, pos, "[non-configurable property: #{name}]",
          "[attempted to change the property descriptor of property: #{name}]", parents

      Object.defineProperty obj, name, desc

    handler["delete"] = (name) ->
      res = undefined
      invariant = undefined
      # have to reverse blame since the client is the one calling delete
      if options.sealed or options.frozen
        blame neg, pos, "#{if options.sealed then 'sealed' else 'frozen'} object",
          "[call to delete]", parents

      res = delete obj[name]

      if options.invariant
        invariant = options.invariant.bind(obj)
        blame neg, pos, "invariant: #{options.invariant.toString()}", obj, parents  unless invariant()
      res

    handler["get"] = (receiver, name) ->
      if that.oc.hasOwnProperty(name)
        obj and that.oc[name].value.check obj[name], pos, neg, parents
      else if (options.arrayRangeContract and (options.arrayRange isnt `undefined`)) and (parseInt(name, 10) >= options.arrayRange)
        obj and options.arrayRangeContract.check obj[name], pos, neg, parents
      else
        obj and obj[name]

    handler.set = (receiver, name, val) ->
      if (options.extensible is false) and Object.getOwnPropertyDescriptor(obj, name) is undefined
        blame neg, pos, "non-extensible object", "[attempted to set a new property: #{name}]", parents

      if options.frozen
        blame neg, pos, "frozen object", "[attempted to set: #{name}]", parents

      if that.oc.hasOwnProperty(name)
        if not that.oc[name].writable
          blame neg, pos, "read-only property", "[attempted to set read-only property: #{name}]", parents
        # have to reverse blame since the client is the one calling set
        obj[name] = that.oc[name]["value"].check(val, neg, pos, parents)
      else if (options.arrayRangeContract and (options.arrayRange isnt undefined)) and (parseInt(name, 10) >= options.arrayRange)
        obj[name] = options.arrayRangeContract.check(val, neg, pos, parents)
      else
        obj[name] = val
      if options.invariant
        invariant = options.invariant.bind(obj)
        blame neg, pos, "invariant: #{options.invariant.toString()}", obj, parents  unless invariant()
      true

    # making this a function proxy if object is also a
    # function to preserve typeof checks
    if typeof obj is "function"
      try
        op = new Proxy(obj, handler)
        handler["construct"] = (target, args)->
          objProto = Object.create(op.prototype);
          instance = target.apply(objProto, args);
          result =  (typeof instance is "object" and instance ) or objProto;
          if options.class
            options.class.check result, pos, neg, parents
          else
            result
        handler["apply"] = (target, thisArg, args)->
          target.apply thisArg, args
      catch e

        op = Proxy.createFunction(handler, (args) ->
          obj.apply this, arguments
        , (args) ->
          objProto = Object.create(op.prototype);
          instance = op.apply(objProto, arguments);
          result = (typeof instance is 'object' and instance ) or objProto;
          if options.class
            options.class.check result, pos, neg, parents
          else
            result
        )
    else
      proto = if obj is null then null else Object.getPrototypeOf obj
      try
        op = new Proxy(obj, handler)
      catch e
        # V8 hasn't implemented direct proxies yet so failback to old api
        op = Proxy.create(handler, proto)

    unproxy.set op, this
    op
  )
  c.oc = objContract
  c.raw_options = options


  # hook up the recursive contracts if they exist
  setSelfContracts = (c, toset) ->
    # all the different possible children names from the combinators (really kludgy)
    childrenNames = [ "k", "k1", "k2", "flats", "ho", "calldom", "callrng", "newdom", "newrng" ]
    # check each of the properties in an object contract
    if typeof c.oc isnt "undefined"
      for name of c.oc
        # if this prop is the self contract replace it with the contract reference
        if c.oc[name] is self
          c.oc[name] = toset
        # otherwise if it's a function contract then there might be nested
        # self contracts so dive into them with the original toset reference
        else
          setSelfContracts c.oc[name], toset  if c.oc[name].ctype isnt "object"
        # note that we don't dive into object contracts...each self contract
        # thus binds to its enclosing object contract
    else
      # run through each of the children contracts (sorry, pretty kludgy)
      childrenNames.forEach (cName) ->
        if typeof c[cName] isnt "undefined"
          # the if stored in an array go through those first
          if Array.isArray(c[cName])
            i = 0
            while i < c[cName].length
              if c[cName][i] is self
                c[cName][i] = toset
              else
                # dive into nested contracts with the original toset reference
                setSelfContracts c[cName][i], toset  if c[cName][i].ctype isnt "object"
              i++
          else
            if c[cName] is self
              c[cName] = toset
            else setSelfContracts c[cName], toset  if c[cName] isnt "object"


  setSelfContracts c, c
  c.equals = (other) ->
    return false  if not other instanceof Contract or other.ctype isnt @ctype
    checkOptions(@oc, other.oc) and checkOptions(@raw_options, other.raw_options)
  c


___ = (k) -> deferred: k

arr = (ks) ->
  # todo might make sense to allow var args along with array arguments
  oc = {}
  name = ""
  prefix = ""
  i = 0
  while i < ks.length
    prefix = ", "  if i isnt 0
    if ks[i].deferred
      throw new Error "___() must be at the last position in the array"  if i isnt ks.length - 1
      throw new Error "value given to ___ is not a contract" if not (ks[i].deferred instanceof Contract)
      rangeContract = ks[i].deferred
      rangeIndex = i
      name += prefix + "..." + rangeContract.cname
    else
      oc[i] = ks[i]
      name += prefix + ks[i].cname
    i++
  name = "[" + name + "]"
  object oc,
    arrayRange: rangeIndex
    arrayRangeContract: rangeContract
  , name


or_ = ->
  ks = [].slice.call(arguments)

  ks.forEach (el, idx) ->
    if not (el instanceof Contract)
      throw new Error "Argument #{idx} to the `or` contract is not a contract"

  flats = ks.filter (el) -> el.ctype is "check"
  ho = ks.filter (el) -> el.ctype isnt "check"
  throw new Error "Cannot have more than 1 higher order contract in 'or'"  if ho.length > 1

  name = ks.join(" or ")
  c = new Contract(name, "or", (val, pos, neg, parentKs) ->
    parents = parentKs.slice(0)
    parents.push this

    i = 0
    while i < flats.length
      try
        return @flats[i].check(val, pos, neg, parents)
      catch e
        lastBlame = e
        i++

    if ho.length is 1
      @ho[0].check val, pos, neg, parents
    else
      throw lastBlame # the last contract in the array still assigned blame so surface it
  )

  c.flats = flats
  c.ho = ho
  c.equals = (other) ->
    return false  if not other instanceof Contract or other.ctype isnt @ctype
    zipFlats = Utils.zip(@flats, other.flats)
    pFlats = (zipFlats.length isnt 0) and zipFlats.every((zf) ->
      zf[0].equals zf[1]
    )

    ho_eq = if (@ho.length is 1 and other.ho.length is 1)
      @ho[0].equals other.ho[0]
    else
      true

    pFlats and ho_eq
  c

and_ = (k1, k2) ->
  if not (k1 instanceof Contract)
    throw new Error "Argument 0 to the `and` contract is not a contract"
  if not (k2 instanceof Contract)
    throw new Error "Argument 1 to the `and` contract is not a contract"

  c = new Contract "#{k1.cname} and #{k2.cname}", "and", (val, pos, neg, parentKs) ->
    k1c = k1.check(val, pos, neg, parentKs)
    k2.check k1c, pos, neg, parentKs

  c.k1 = k1
  c.k2 = k2

  c.equals = (other) ->
    return false  if not other instanceof Contract or other.ctype isnt @ctype
    (@k1.equals(other.k1)) and (@k2.equals(other.k2))

  c

###class_ = (static_, instance, construct)->
  args = Array::slice.call(arguments)
  if not (static_ instanceof Contract)
    throw new Error "Argument 0 to the `and` contract is not a contract"
  if not (instance instanceof Contract)
    throw new Error "Argument 1 to the `and` contract is not a contract"
  if not (construct instanceof Contract)
    throw new Error "Argument 1 to the `and` contract is not a contract"

  if not (static_.ctype is "object")
    throw new Error "Expected the first argument to be an object contract"
  if not (instance.ctype is "object")
    throw new Error "Expected the second argument to be an object contract"
  if not (instance.ctype is "fun")
    throw new Error "Expected the third argument to be a function contract"

  c = new Contract
  c = new Contract ""###

not_ = (k) ->
  if not (k instanceof Contract)
    throw new Error "Argument to the `not` contract is not a contract"

  throw new Error "cannot construct a 'not' contract with a function or object contract"  if k.ctype is "fun" or k.ctype is "object"

  c = new Contract "not #{k.cname}", "not", (val, pos, neg, parentKs) ->
    try
      res = @k.check(val, pos, neg, parentKs)
      blame pos, neg, this, val, parentKs
    catch b
      # inverting the original contract so return ok
      return res

  c.k = k

  c.equals = (other) ->
    return false  if not other instanceof Contract or other.ctype isnt @ctype
    @k.equals other.k
  c

opt = (k) ->
  if not (k instanceof Contract)
    throw new Error "Argument to the `optional` contract is not a contract"

  c = new Contract "opt(#{k.cname})", "opt", (val, pos, neg, parentKs) ->
    if val is undefined
      # unsuplied arguments are just passed through
      val
    else
      # arg is actually something so check the underlying contract
      @k.check val, pos, neg, parentKs

  c.k = k
  c.equals = (other) ->
    return false  if not other instanceof Contract or other.ctype isnt @ctype
    @k.equals other.k
  c

# note that this function is particular about where it is called from.
# it gets the filename/linenum combo from the file that called the
# function that called getModName (two levels up the stack).
# () -> ModuleName
getModName = (isServer) ->
  st = printStackTrace(e: new Error())
  # in the stacktrace the frame above this one is where we were guarded/used
  guardedAt = if st[0] is 'Error' then st[3] else st[2]
  # pull out the filename (which will become our module) and line
  # number (the location in the module where the guard/use occured)
  # stack traces look like: {anonymous}()@file:///Path/to/file.js:4242
  match = /\/([^\/]*):(\d*)[\)]?$/.exec(guardedAt)

  if match
    filename = match[1]
    linenum = match[2]
  else
    filename = "unknown"
    linenum = "-1"

  new ModuleName(filename, linenum, isServer)

guard = (k, x, server, setup) ->
  return x if not enabled

  stack = []
  setup stack  if typeof setup is "function"
  unless server?
    # if a server wasn't provied, guess if from the stacktrace
    server = getModName(true)
  else
    server = new ModuleName(server, "", true)

  client = new ModuleName server.filename, "#{server.linenum} (caller)", false
  server.linenum = "#{server.linenum} (value)"

  # unless k is just a first-order contract, c will be a proxy
  c = k.check x, server, client, [], stack

  # in the future we can get back the uncontracted value and contract if
  # given the contracted value (for use in module wrangling)
  contract_orig_map.set c, {originalValue: x, originalContract: k, server: "", }

  if not enabled then x else c

any = (->
  c = new Contract("any", "any", (val) ->
    val
  )
  c.equals = (other) ->
    this is other
  c
)()

self = (->
  c = new Contract("self", "self", (val) ->
    val
  )
  c.equals = (other) ->
    this is other
  c
)()

none = (->
  c = new Contract("none", "none", (val, pos, neg, parentKs) ->
    blame pos, neg, this, val, parentKs
  )
  c.equals = (other) ->
    this is other
  c
)()

# contracts
root.Undefined = check ((x) -> undefined is x), "Undefined"
root.Null      = check ((x) -> null is x), "Null"
root.Num       = check ((x) -> typeof (x) is "number"), "Num"
root.Bool      = check ((x) -> typeof (x) is "boolean"), "Bool"
root.Str       = check ((x) -> typeof (x) is "string"), "Str"
root.Odd       = check ((x) -> (x % 2) is 1), "Odd"
root.Even      = check ((x) -> (x % 2) isnt 1), "Even"
root.Pos       = check ((x) -> x >= 0), "Pos"
root.Nat       = check ((x) -> x > 0), "Nat"
root.Neg       = check ((x) -> x < 0), "Neg"
root.Arr       = object(length: check ((x) -> typeof (x) is "number"), "Number")
root.Self      = self
root.Any       = any
root.None      = none
# combinators
root.check     = check
root.fun       = fun
root.ctor      = ctor
root.ctorSafe  = ctorSafe
root.object    = object
root.arr       = arr
root.___       = ___
root.any       = any
root.or        = or_
root.none      = none
root.not       = not_
root.and       = and_
root.opt       = opt
root.guard     = guard
root.extend    = extend
root.overload_fun = overload_fun
# utility functions

# for use with commonjs.
# creates an exports object that records the
# server module name whenever a contracted value is added.
# root.exports :: (Str, {}?) -> {}
root.exports = (moduleName, original = {}) ->
  handler = idHandler original
  handler.set = (r, name, value) ->
    if (value isnt null) and typeof value is "object" or typeof value is "function"
      orig = contract_orig_map.get value
    if orig?
      {originalValue, originalContract} = orig
      # make a note of the server's module name in the map
      contract_orig_map.set value,
        originalValue: originalValue
        originalContract: originalContract
        server: moduleName
    original[name] = value
    return
  Proxy.create handler

# for use with AMD.
# goes through each value on the export object and
# if it is a contracted value sets the server name.
# Similar to "exports" but does the work after values
# have been added to the object.
# root.setExported :: ({}, Str) -> {}
root.setExported = (exportObj, moduleName) ->

  replaceOrig = (value)->
    orig = null
    if (value isnt null) and typeof value is "object" or typeof value is "function"
      orig = contract_orig_map.get value
    if orig?
      {originalValue, originalContract} = orig
      # make a note of the server's module name in the map
      contract_orig_map.set value,
        originalValue: originalValue
        originalContract: originalContract
        server: moduleName

  if exportObj instanceof Contract
    replaceOrig exportObj
  else
    for own name, value of exportObj
      #prevents orig? branch being executed with malicious data.
      #i.e. orig can be set from previous loop and we would then set
      #orig with the new value if it doesn't pass the first test.
      replaceOrig value
  exportObj

# takes an exports object and sets the client module name
# for every contracted value.
# root.use :: ({}, Str) -> {}
root.use = (exportObj, moduleName) ->
  res = {}

  getCorrectModuleName = (orig)->
    if typeof orig.server is "string"
      mod = new ModuleName(orig.server, "", true)
    else
      mod = orig.server
    mod

  getOrig = (value)->
    orig = null
    if (value isnt null) and typeof value is "object" or typeof value is "function"
      orig = contract_orig_map.get value
    orig

  if exportObj instanceof Contract
    orig = getOrig exportObj
    if orig?
      mod = getCorrectModuleName orig
      res = orig.originalContract.check orig.originalValue, mod, moduleName, []
      res
    else
      exportObj

  if typeof exportObj is "function"
    # return early...don't support wrapping functions ATM
    exportObj
  else
    for own name, value of exportObj
      orig = null
      orig = getOrig value
      if orig?
        mod = getCorrectModuleName orig
        res[name] = orig.originalContract.check orig.originalValue, mod, moduleName, []
      else
        res[name] = value
    res



root.enabled = (b) -> enabled = b
# puts every exported function onto the global scope
root.autoload  = ->
  globalObj = window ? global # browser or node
  globalObj[name] = root[name] for own name of root when (name isnt "use") and (name isnt "exports")
  return

root.show_parent_contracts = (b) -> show_parent_contracts = b

# use either AMD, Node, or the global object
((define) -> define 'contracts-js', (require) -> root
)(if typeof define is 'function' and define.amd then define else (id, factory) ->
  if typeof module isnt 'undefined' and module.exports
    # in node
    module.exports = factory require
  else
    window[id] = factory (value) -> window[value]
)
