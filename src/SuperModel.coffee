xhr = require 'xhr'
$q = require 'q'

deepCopy = (obj) ->
  # Emulate angular.copy, quick and dirty
  JSON.parse(JSON.stringify(obj))

makeHttpRequest = (method, url, body, contentType) ->
  dfd = $q.defer()
  requestOptions =  {
    method
    url
    body
    headers:
      'Content-Type': contentType
  }
  console.log "Making HTTP request", requestOptions
  xhr requestOptions, (err, response, body) ->
    if (err)
      dfd.reject(err)
    else
      # FIXME: Change the code that depends on response.headers()
      response.headers = (headerName) ->
        response.headers(headerName)

      # FIXME: Change the code that depends on response.data
      response.data = response.response

      dfd.resolve(response)
  dfd.promise

transformKeys = (obj, transformFun) ->
  o = {}
  o[transformFun(k)] = v  for own k, v of obj
  o

toS = {}.toString

type = (obj) ->
  toS.call(obj).slice(8, -1).toLowerCase()

camelize = (str) ->
  str.substr(0, 1) + str.substr(1).replace /_([a-zA-Z])/g, (g) ->
    g[1].toUpperCase()

unCamelize = (str) ->
  str.replace(
    /([^A-Z])([A-Z])/g, (g) -> g[0] + '_' + g[1].toLowerCase()
  ).toLowerCase()

camelizeKeys = (obj) ->
  transformKeys(obj, camelize)

unCamelizeKeys = (obj) ->
  transformKeys(obj, unCamelize)


class SuperModel
  # Override with e.g.
  # @attrs = {id: 'number', name: 'string', variable: 'number|string'}
  # or @attrs = null if you don't want to be strict about the allowed attrs.
  # We are assuming that no attrs start with '$'.
  @attrs = null
  @collectionUrl = '/'
  @contentType = 'application/json'

  @getUrl = (options = {}) ->
    if Object.keys(options).length is 0
      @collectionUrl
    else if options.id?
      "#{@collectionUrl}/#{options.id}"
    else
      "#{@collectionUrl}#{@makeQS(options)}"

  @makeQS = (opts = {}) ->
    if Object.keys(opts).length is 0
      ''
    else
      '?' + $.param(opts)

  @toBackendFormat = (x) -> JSON.stringify(unCamelizeKeys(x))
  @fromBackendFormat = (x) -> campelizeKeys(JSON.parse(x))

  @makeInstanceFromBackend = (serverResponseBody) ->
    attrs = @fromBackendFormat(serverResponseBody)
    new this attrs, {$isNew: false}

  @fetchAll = (options) ->
    @sync('GET', @getUrl(options))
      .then (response) =>
        @makeInstanceFromBackend(json) for json in response.data

  @fetchById = (id) ->
    throw new Error 'Missing id argument'  unless id?
    @sync('GET', @getUrl({id}))
      .then (response) =>
        @makeInstanceFromBackend(response.data)

  @sync = (method, url, data) ->
    makeHttpRequest(method, url, data, @contentType)

  @seal = ->
    Object.seal(this)
    Object.preventExtensions(this)
    this


  constructor: (attrs = {}, options = {}) ->
    @_defineProperties()  if @_isStrictlyTyped()
    @set(attrs)
    @$location = options.$location ? null
    @$location ?= @constructor.collectionUrl + '/' + @id  if @id?
    @$isNew = options.$isNew ? true
    if @_isStrictlyTyped()
      Object.seal(this)
      Object.preventExtensions(this)

  getProperty: (name, options) ->
    qs = @constructor.makeQS(options)
    @constructor
      .sync('GET', "#{@$location}/#{name}#{qs}")
      .then ({data}) =>
        data
      .catch (err) =>
        $q.reject(err)

  putProperty: (name, value, options) ->
    qs = @constructor.makeQS(options)
    @constructor
      .sync('PUT', "#{@$location}/#{name}#{qs}", value)
      .then ({data}) =>
        data

  # FIXME: DRY
  postProperty: (name, value, options) ->
    qs = @constructor.makeQS(options)
    @constructor
      .sync('POST', "#{@$location}/#{name}#{qs}", value)
      .then ({data}) =>
        data

  set: (attrs = {}) ->
    for k, v of attrs
      @_checkAttrName k
      if v isnt undefined
        @_checkAttrType k, type(v)
      @_setAttr k, v
    this

  toJSON: ->
    if @_isStrictlyTyped()
      # Only export the defined attrs.
      deepCopy(@attrs)
    else
      # Export all properties apart from the internal keys.
      obj = {}
      for own key, val of this
        obj[key] = deepCopy(val)  if key[0] isnt '$'
      obj

  save: (urlOptions = {}) ->
    data = @toJSON()
    delete data.id
    if @constructor.toBackendFormat
      data = @constructor.toBackendFormat(data)
    promise = if @$isNew
      @_create data, urlOptions
    else
      @_update data
    promise
      .then =>
        @$isNew = false
        this

  delete: () ->
    if @$isNew
      return @_deferSelf()
    throw new Error 'No $location'  unless @$location?
    @constructor.sync('DELETE', @$location)
      .then =>
        @$cleanup?()
        this


  _setAttr: (key, value) ->
    attrsObject = if @_isStrictlyTyped() then @attrs else this
    attrsObject[key] = value

  _isStrictlyTyped: ->
    !! @constructor.attrs?

  _checkAttrName: (key) ->
    validAttrs = @constructor.attrs
    if validAttrs? and key not of validAttrs
      throw new Error "No such attr: #{key}"

  _checkAttrType: (key, valueType) ->
    types = @constructor.attrs?[key]
    if types? and valueType not in types.split('|')
      throw new Error "Bad type #{key}: #{valueType}, allowed: #{types}"

  _create: (data, urlOptions) ->
    @constructor.sync('POST', @constructor.getUrl(urlOptions), data)
      .then (response) =>
        @$isNew = false
        @$location = response.headers('location')
        if not @id?
          m = @$location.match(/\/(\d+)$/)
          if m?
            @id = +m[1]
        this

  _update: (data) ->
    throw new Error 'No $location'  unless @$location?
    @constructor.sync('PUT', @$location, data)
      .then =>
        this

  _deferSelf: ->
    dfd = $q.defer()
    dfd.resolve this
    dfd.promise

  _defineProperties: ->
    # Support ng-repeat's modifications of the object:
    Object.defineProperty this, '$$hashKey',
      configurable: true
      writable: true
      enumerable: true
    Object.defineProperty this, 'attrs', value: {}
    for prop, types of @constructor.attrs
      do (types, prop) =>
        Object.defineProperty this, prop,
          enumerable: true
          set: (value) =>
            if value isnt undefined
              @_checkAttrType prop, type(value)
            @_setAttr prop, value
          get: =>
            @attrs[prop]


Object.seal(SuperModel.prototype)
SuperModel = SuperModel.seal()
module.exports = SuperModel

# FIXME. Quick and dirty testing for now:
if require.main is module

  class FooModel extends SuperModel
    @collectionUrl = 'http://httpbin.org/status'

  FooModel.fetchById(418)
