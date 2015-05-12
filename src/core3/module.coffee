class Layout extends D.View
    initialize: ->
        @isLayout = true
        @loadDeferred = @chain [@loadTemplate(), @loadHandlers()]
        delete @bindData

    setRegion: ->
        super
        @regionInfo = @module.regionInfo

D.Module = class Module extends D.Base
    @Layout = Layout
    constructor: (@name, @app, @loader, @options = {}) ->
        [..., @baseName] = @name.split '/'
        @separatedTemplate = @options.separatedTemplate is true
        @regions = {}
        super 'M'
        @app.modules[@id] = @
        @app.delegateEvent @

    initialize: ->
        @extend @options.extend if @options.extend
        @loadDeferred = @createDeferred()
        @chain [@loadTemplate(), @loadLayout(), @loadData(), @loadItems()], -> @loadDeferred.resolve()

    loadTemplate: ->
        return if @separatedTemplate
        @chain @loader.loadTemplate(@), (template) -> @template = template

    loadLayout: ->
        layout = @getOptionResult @options.layout
        name = if D.isString layout then layout else layout?.name
        name or= 'layout'
        @chain @app.getLoader(name).loadLayout(@, name, layout), (obj) =>
            @layout = obj

    loadData: ->
        @data = {}
        promises = []
        items = @getOptionResult(@options.data) or {}
        @autoLoadDuringRender = []
        @autoLoadAfterRender = []

        doLoad = (id, value) =>
            name = D.Loader.analyse(id).name
            value = @getOptionResult value
            if value
                if value.autoLoad is 'after' or value.autoLoad is 'afterRender'
                    @autoLoadAfterRender.push name
                else if value.autoLoad
                    @autoLoadDuringRender.push name
            promises.push @chain @app.getLoader(id).loadModel(value, @), (d) -> @data[name] = d

        doLoad id, value for id, value of items

        @chain promises

    loadItems: ->
        @items = {}
        @inRegionItems = []

        promises = []
        items = @getOptionResult(@options.items) or []
        doLoad = (name, item) =>
            item = @getOptionResult item
            item = region: item if item and D.isString item
            isModule = item.isModule

            p = @chain @app.getLoader(name)[if isModule then 'loadModule' else 'loadView'](name, @, item), (obj) =>
                @items[obj.name] = obj
                obj.regionInfo = item
                @inRegionItems.push obj if item.region
            promises.push p

        doLoad name, item for name, item of items

        @chain promises

    addRegion: (name, el) ->
        type = el.data 'region-type'
        @regions[name] = Region.create type, @app, @, el

    removeRegion: (name) ->
        delete @regions[name]

    render: (options = {}) ->
        throw new Error 'No region to render in' unless @region
        @renderOptions = options

        @chain(
            @loadDeferred
            -> @options.beforeRender?.apply @
            -> @layout.setRegion @region
            @fetchDataDuringRender
            -> @layout.render()
            -> @options.afterLayoutRender?.apply @
            ->
                defers = for value in @inRegionItems
                    key = value.regionInfo.region
                    region = @regions[key]
                    throw new Error "Can not find region: #{key}" unless region
                    region.show value
                $.when defers...
            -> @options.afterRender?.apply @
            @fetchDataAfterRender
            @
        )

    setRegion: (@region) ->

    close: -> @chain(
        -> @options.beforeClose?.apply @
        -> @layout.close()
        -> value.close() for key, value of @regions
        -> @options.afterClose?.apply @
        -> delete @app.modules[@id]
        @
    )

    fetchDataDuringRender: ->
        @chain (@data[id].get?() for id in @autoLoadDuringRender)

    fetchDataAfterRender: ->
        @chain (@data[id].get?() for id in @autoLoadAfterRender)