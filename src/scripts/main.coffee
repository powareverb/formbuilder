class FormbuilderModel extends Backbone.DeepModel
  sync: -> # noop
  indexInDOM: ->
    $wrapper = $(".fb-field-wrapper").filter ( (_, el) => $(el).data('cid') == @cid  )
    $(".fb-field-wrapper").index $wrapper
  is_input: ->
    Formbuilder.inputFields[@get(Formbuilder.options.mappings.FIELD_TYPE)]?


class FormbuilderCollection extends Backbone.Collection
  initialize: ->
    @on 'add', @copyCidToModel

  model: FormbuilderModel

  comparator: (model) ->
    model.indexInDOM()

  copyCidToModel: (model) ->
    model.attributes.cid = model.cid


class ViewFieldView extends Backbone.View
  className: "fb-field-wrapper"

  events:
    'click .subtemplate-wrapper': 'focusEditView'
    'click .js-duplicate': 'duplicate'
    'click .js-clear': 'clear'

  initialize: (options) ->
    {@parentView} = options
    @listenTo @model, "change", @render
    @listenTo @model, "destroy", @remove

  render: ->
    @$el.addClass('response-field-' + @model.get(Formbuilder.options.mappings.FIELD_TYPE))
        .data('cid', @model.cid)
        .html(Formbuilder.templates["view/base#{if !@model.is_input() then '_non_input' else ''}"]({rf: @model}))

    return @

  focusEditView: ->
    @parentView.createAndShowEditView(@model)

  clear: (e) ->
    e.preventDefault()
    e.stopPropagation()

    cb = =>
      @parentView.handleFormUpdate()
      @model.destroy()

    x = Formbuilder.options.CLEAR_FIELD_CONFIRM

    switch typeof x
      when 'string'
        if confirm(x) then cb()
      when 'function'
        x(cb)
      else
        cb()

  duplicate: ->
    attrs = jQuery.extend(true, {}, @model.attributes);
    delete attrs['id']
    attrs['label'] += ' Copy'
    option['key'] = _.uniqueId('option_') for option in attrs.field_options.options
    @parentView.createField attrs, { position: @model.indexInDOM() + 1 }

class FormPropertiesView extends Backbone.View
  className: "form-properties-field"
  events:
    'input .form-name-input' : 'forceRender'
  initialize: (options) ->
    {@parentView} = options
    @el = $('.fb-form-props')
    @_ensureElement()
  render: ->
    rivets.bind @$el, { model: @model }
    @
  forceRender: ->
    @model.trigger('change')
    #@parentView.handleFormUpdate()

class EditFieldView extends Backbone.View
  className: "edit-response-field"

  events:
    'click .js-add-option'      : 'addOption'
    'click .js-remove-option'   : 'removeOption'
    'click .js-default-updated' : 'defaultUpdated'
    'focus #grNameDialog'       : 'triggerGroup'
    'input .option-label-input' : 'forceRender'

  initialize: (options) ->
    {@parentView} = options
    @listenTo @model, "destroy", @remove

  onDropboxClose: (event, ui)->
    $('.ui-autocomplete-input').change()

  render: ->
    @$el.html(Formbuilder.templates["edit/base#{if !@model.is_input() then '_non_input' else ''}"]({rf: @model}))
    rivets.bind @$el, { model: @model }

    @$( "#grName" ).autocomplete({
        source: @getGroups(),
        minLength: 0,
        close: @onDropboxClose
    }).focus(->
      $(this).val ''
      $(this).autocomplete 'search'
      @)

    @$("#grName").attr('autocomplete', 'on')

    $.ajax {
      type: "GET",
      url: "getFieldsList",
      dataType: "json",
      data: {field_type: @model.get(Formbuilder.options.mappings.FIELD_TYPE)},
      contentType: "application/json; charset=utf-8",
      success: (data)=>
        partial = (onChangeFn, data)->
          (event, ui) -> onChangeFn(data, event, ui)

        onChange = (data, event, ui)=>
          options = []
          if @model.get(Formbuilder.options.mappings.BIND) != event.target.value and event.target.value!=''
            if obj = $.grep(data, (item)->item.value==event.target.value)[0]?.options
              (options.push({label: val, checked: false, key: key}) for key, val of option for option in obj)

          @model.set Formbuilder.options.mappings.OPTIONS, options
          @model.trigger "change:#{Formbuilder.options.mappings.OPTIONS}"

          $('.ui-autocomplete-input').change()
          $(event.target).blur()


          @forceRender()

        @$( "#D4W_data" ).autocomplete({
          source:    data,
          minLength: 0,
          close: partial(onChange, data)
        }).focus(->
          $(this).val ''
          $(this).autocomplete 'search'
          @)

        @$("#D4W_data").attr('autocomplete', 'on')
      error: (XMLHttpRequest, textStatus, errorThrown)->
         alert(textStatus);
    }

    #damned rivets does not support arrays
    @$el.find("#grNameDialog").each (index, element) =>
      $(element).val(@model.attributes.field_options.options[index].tr_group)

    return @

  remove: ->
    @onDropboxClose()
    @parentView.editView = undefined
    @parentView.$el.find("[data-target=\"#addField\"]").click()
    super

  # @todo this should really be on the model, not the view
  addOption: (e) ->
    $el       = $(e.currentTarget)
    i         = @$el.find('.option').index($el.closest('.option'))
    options   = @model.get(Formbuilder.options.mappings.OPTIONS) || []
    newOption = {label: "", checked: false, key: _.uniqueId('option_')}

    if i > -1
      options.splice(i + 1, 0, newOption)
    else
      options.push newOption

    @model.set Formbuilder.options.mappings.OPTIONS, options
    @model.trigger "change:#{Formbuilder.options.mappings.OPTIONS}"
    @forceRender()

  removeOption: (e) ->
    $el     = $(e.currentTarget)
    index   = @$el.find(".js-remove-option").index($el)
    options = @model.get Formbuilder.options.mappings.OPTIONS

    options.splice index, 1

    @model.set Formbuilder.options.mappings.OPTIONS, options
    @model.trigger "change:#{Formbuilder.options.mappings.OPTIONS}"
    @forceRender()

  defaultUpdated: (e) ->
    $el = $(e.currentTarget)

    unless @model.get(Formbuilder.options.mappings.FIELD_TYPE) == 'checkboxes' # checkboxes can have multiple options selected
      @$el.find(".js-default-updated").not($el).attr('checked', false).trigger('change')

    @forceRender()

  forceRender: ->
    @model.trigger('change')

  getGroups: ->
    options = _.pluck(@model.collection.models, 'attributes')
    options = _.pluck(options, 'group')
    options = _.uniq(_.compact(options))
    #options.unshift("")
    return options

  triggerGroup: (e) ->
    b = $(e.currentTarget)

    options=@model.get Formbuilder.options.mappings.OPTIONS
    $el = $(e.currentTarget)
    i = @$el.find('.option').index($el.closest('.option'))

    fn = do (i, options ) -> ->
      if i > -1
        options[i].tr_group = b.val()
      $('.ui-autocomplete-input').change()

    b.autocomplete({
        source: @getGroups(),
        minLength: 0,
        close: => fn()
    }).focus(->
      $(this).val ''
      $(this).autocomplete 'search'
      @)

    b.attr('autocomplete','on')

    @forceRender()

class BuilderView extends Backbone.View
  SUBVIEWS: []

  events:
    'click .js-save-form': 'saveForm'
    'click .fb-tabs a': 'showTab'
    'click .fb-add-field-types a': 'addField'
    'mouseover .fb-add-field-types': 'lockLeftWrapper'
    'mouseout .fb-add-field-types': 'unlockLeftWrapper'

  initialize: (options) ->
    {selector, @formBuilder, @bootstrapData, @form_name, @url} = options
    @SUBVIEWS.push FormPropertiesView
    # This is a terrible idea because it's not scoped to this view.
    if selector?
      @setElement $(selector)

    # Create the collection, and bind the appropriate events
    @collection = new FormbuilderCollection
    @collection.bind 'add', @addOne, @
    @collection.bind 'reset', @reset, @
    @collection.bind 'change', @handleFormUpdate, @
    @collection.bind 'destroy add reset', @hideShowNoResponseFields, @
    @collection.bind 'destroy', @ensureEditViewScrolled, @

    @form_model = new FormbuilderModel({form_name:@form_name})

    @render()
    @collection.reset(@bootstrapData)
    # Render any subviews (this is an easy way of extending the Formbuilder)
    new subview({parentView: @, model: @form_model}).render() for subview in @SUBVIEWS

    @bindSaveEvent()

  bindSaveEvent: ->
    @formSaved = true
    @saveFormButton = @$el.find(".js-save-form")
    @saveFormButton.attr('disabled', true).text(Formbuilder.options.dict.ALL_CHANGES_SAVED)

    unless !Formbuilder.options.AUTOSAVE
      @renew = setInterval =>
        @saveForm.call(@)
      , 5000

    $(window).bind 'beforeunload', =>
      if @formSaved then undefined else Formbuilder.options.dict.UNSAVED_CHANGES

  reset: ->

    @$responseFields.html('')
    @addAll()

  render: ->
    @$el.html Formbuilder.templates['page']()
    # Save jQuery objects for easy use
    @$fbLeft = @$el.find('.fb-left')
    @$responseFields = @$el.find('.fb-response-fields')

    @bindWindowScrollEvent()
    @hideShowNoResponseFields()

    return @

  bindWindowScrollEvent: ->
    $(window).on 'scroll', =>
      return if @$fbLeft.data('locked') == true
      newMargin = Math.max(0, $(window).scrollTop() - @$el.offset().top)
      maxMargin = @$responseFields.height()

      @$fbLeft.css
        'margin-top': Math.min(maxMargin, newMargin)

  showTab: (e) ->
    $el = $(e.currentTarget)
    target = $el.data('target')
    $el.closest('li').addClass('active').siblings('li').removeClass('active')
    $(target).addClass('active').siblings('.fb-tab-pane').removeClass('active')

    @unlockLeftWrapper() unless target == '#editField'

    if target == '#editField' && !@editView && (first_model = @collection.models[0])
      @createAndShowEditView(first_model)

  addOne: (responseField, _, options) ->
    view = new ViewFieldView
      model: responseField
      parentView: @

    #####
    # Calculates where to place this new field.
    #
    # Are we replacing a temporarily drag placeholder?
    if options.$replaceEl?
      options.$replaceEl.replaceWith(view.render().el)

    # Are we adding to the bottom?
    else if !options.position? || options.position == -1
      @$responseFields.append view.render().el

    # Are we adding to the top?
    else if options.position == 0
      @$responseFields.prepend view.render().el

    # Are we adding below an existing field?
    else if ($replacePosition = @$responseFields.find(".fb-field-wrapper").eq(options.position))[0]
      $replacePosition.before view.render().el

    # Catch-all: add to bottom
    else
      @$responseFields.append view.render().el

  setSortable: ->
    @$responseFields.sortable('destroy') if @$responseFields.hasClass('ui-sortable')
    @$responseFields.sortable
      forcePlaceholderSize: true
      placeholder: 'sortable-placeholder'
      stop: (e, ui) =>
        if ui.item.data('field-type')
          rf = @collection.create Formbuilder.helpers.defaultFieldAttrs(ui.item.data('field-type')), {$replaceEl: ui.item}
          @createAndShowEditView(rf)

        @handleFormUpdate()
        return true
      update: (e, ui) =>
        # ensureEditViewScrolled, unless we're updating from the draggable
        @ensureEditViewScrolled() unless ui.item.data('field-type')

    @setDraggable()

  setDraggable: ->
    $addFieldButtons = @$el.find("[data-field-type]")

    $addFieldButtons.draggable
      connectToSortable: @$responseFields
      helper: =>
        $helper = $("<div class='response-field-draggable-helper' />")
        $helper.css
          width: @$responseFields.width() # hacky, won't get set without inline style
          height: '80px'

        $helper

  addAll: ->
    @collection.each @addOne, @
    @setSortable()

  hideShowNoResponseFields: ->
    @$el.find(".fb-no-response-fields")[if @collection.length > 0 then 'hide' else 'show']()

  addField: (e) ->
    field_type = $(e.currentTarget).data('field-type')
    @createField Formbuilder.helpers.defaultFieldAttrs(field_type)

  createField: (attrs, options) ->
    rf = @collection.create attrs, options
    @createAndShowEditView(rf)
    @handleFormUpdate()

  createAndShowEditView: (model) ->
    $responseFieldEl = @$el.find(".fb-field-wrapper").filter( -> $(@).data('cid') == model.cid )
    $responseFieldEl.addClass('editing').siblings('.fb-field-wrapper').removeClass('editing')

    if @editView
      if @editView.model.cid is model.cid
        @$el.find(".fb-tabs a[data-target=\"#editField\"]").click()
        @scrollLeftWrapper($responseFieldEl)
        return

      @editView.remove()

    @editView = new EditFieldView
      model: model
      parentView: @

    $newEditEl = @editView.render().$el
    @$el.find(".fb-edit-field-wrapper").html $newEditEl
    @$el.find(".fb-tabs a[data-target=\"#editField\"]").click()
    @scrollLeftWrapper($responseFieldEl)
    return @

  ensureEditViewScrolled: ->
    return unless @editView
    @scrollLeftWrapper $(".fb-field-wrapper.editing")

  scrollLeftWrapper: ($responseFieldEl) ->
    @unlockLeftWrapper()
    return unless $responseFieldEl[0]
    $.scrollWindowTo ((@$el.offset().top + $responseFieldEl.offset().top) - @$responseFields.offset().top), 200, =>
      @lockLeftWrapper()

  lockLeftWrapper: ->
    @$fbLeft.data('locked', true)

  unlockLeftWrapper: ->
    @$fbLeft.data('locked', false)

  handleFormUpdate: ->
    return if @updatingBatch
    @formSaved = false
    @saveFormButton.removeAttr('disabled').text(Formbuilder.options.dict.SAVE_FORM)

  saveForm: (e) ->
    return if @formSaved
    @formSaved = true
    @saveFormButton.attr('disabled', true).text(Formbuilder.options.dict.ALL_CHANGES_SAVED)
    @collection.sort()

    payload = JSON.stringify($.extend({bootstrapData: @collection.toJSON()},@form_model.toJSON()))
    if Formbuilder.options.HTTP_ENDPOINT then @doAjaxSave(payload)
    @formBuilder.trigger 'save', payload

  doAjaxSave: (payload) ->
    $.ajax
      url: Formbuilder.options.HTTP_ENDPOINT
      type: Formbuilder.options.HTTP_METHOD
      data: payload
      dataType: 'json'
      contentType: "application/json"
      mimeType: 'application/json'
      success: (data) =>
        @updatingBatch = true

        for datum in data
          # set the IDs of new response fields, returned from the server
          @collection.get(datum.cid)?.set({id: datum.id})
          @collection.trigger 'sync'

        @updatingBatch = undefined


class Formbuilder
  @helpers:
    defaultFieldAttrs: (field_type) ->
      attrs = {}
      attrs[Formbuilder.options.mappings.LABEL] = 'Untitled'
      attrs[Formbuilder.options.mappings.FIELD_TYPE] = field_type
      attrs[Formbuilder.options.mappings.REQUIRED] = true
      attrs['field_options'] = {}
      Formbuilder.fields[field_type].defaultAttributes?(attrs) || attrs

    simple_format: (x) ->
      x?.replace(/\n/g, '<br />')

  @options:
    BUTTON_CLASS: 'fb-button'
    HTTP_ENDPOINT: ''
    HTTP_METHOD: 'POST'
    AUTOSAVE: true
    CLEAR_FIELD_CONFIRM: false

    mappings:
      GROUP:          'group'
      BIND:           'd4w_field'
      SIZE:           'field_options.size'
      UNITS:          'field_options.units'
      LABEL:          'label'
      FIELD_TYPE:     'field_type'
      REQUIRED:       'required'
      ADMIN_ONLY:     'admin_only'
      OPTIONS:        'field_options.options'
      DESCRIPTION:    'field_options.description'
      INCLUDE_OTHER:  'field_options.include_other_option'
      INCLUDE_BLANK:  'field_options.include_blank_option'
      INTEGER_ONLY:   'field_options.integer_only'
      MIN:            'field_options.min'
      MAX:            'field_options.max'
      MINLENGTH:      'field_options.minlength'
      MAXLENGTH:      'field_options.maxlength'
      LENGTH_UNITS:   'field_options.min_max_length_units'

    dict:
      ALL_CHANGES_SAVED:  'All changes saved'
      SAVE_FORM:          'Save form'
      UNSAVED_CHANGES:    'You have unsaved changes. If you leave this page, you will lose those changes!'

  @fields: {}
  @inputFields: {}
  @nonInputFields: {}

  @registerField: (name, opts) ->
    for x in ['view', 'edit']
      opts[x] = _.template(opts[x])

    opts.field_type = name

    Formbuilder.fields[name] = opts

    if opts.type == 'non_input'
      Formbuilder.nonInputFields[name] = opts
    else
      Formbuilder.inputFields[name] = opts

  constructor: (opts={}) ->
    _.extend @, Backbone.Events
    args = _.extend opts, {formBuilder: @}
    Formbuilder.options.HTTP_ENDPOINT = opts.url
    @mainView = new BuilderView args
    $( document ).tooltip()

  close: ->
    clearInterval(@mainView.renew)

window.Formbuilder = Formbuilder

if module?
  module.exports = Formbuilder
else
  window.Formbuilder = Formbuilder
