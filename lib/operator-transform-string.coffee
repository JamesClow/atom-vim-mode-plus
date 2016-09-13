LineEndingRegExp = /(?:\n|\r\n)$/
_ = require 'underscore-plus'
{BufferedProcess} = require 'atom'

{
  haveSomeSelection
  isSingleLine
  saveCursorPositions
} = require './utils'
swrap = require './selection-wrapper'
settings = require './settings'
Base = require './base'
Operator = Base.getClass('Operator')

# TransformString
# ================================
transformerRegistry = []
class TransformString extends Operator
  @extend(false)
  trackChange: true
  stayOnLinewise: true
  autoIndent: false

  @registerToSelectList: ->
    transformerRegistry.push(this)

  mutateSelection: (selection) ->
    text = @getNewText(selection.getText(), selection)
    selection.insertText(text, {@autoIndent})

class ToggleCase extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`Hello World` -> `hELLO wORLD`"
  displayName: 'Toggle ~'
  hover: icon: ':toggle-case:', emoji: ':clap:'
  stayAtSamePosition: true

  toggleCase: (char) ->
    charLower = char.toLowerCase()
    if charLower is char
      char.toUpperCase()
    else
      charLower

  getNewText: (text) ->
    text.split('').map(@toggleCase.bind(this)).join('')

class ToggleCaseAndMoveRight extends ToggleCase
  @extend()
  hover: null
  stayAtSamePosition: false
  target: 'MoveRight'
  restoreCursorPositions: ->
    # [FIXME] just for do nothing

class UpperCase extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`Hello World` -> `HELLO WORLD`"
  hover: icon: ':upper-case:', emoji: ':point_up:'
  displayName: 'Upper'
  stayAtSamePosition: true
  getNewText: (text) ->
    text.toUpperCase()

class LowerCase extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`Hello World` -> `hello world`"
  hover: icon: ':lower-case:', emoji: ':point_down:'
  displayName: 'Lower'
  stayAtSamePosition: true
  getNewText: (text) ->
    text.toLowerCase()

# DUP meaning with SplitString need consolidate.
class SplitByCharacter extends TransformString
  @extend()
  @registerToSelectList()
  getNewText: (text) ->
    text.split('').join(' ')

class CamelCase extends TransformString
  @extend()
  @registerToSelectList()
  displayName: 'Camelize'
  @description: "`hello-world` -> `helloWorld`"
  hover: icon: ':camel-case:', emoji: ':camel:'
  getNewText: (text) ->
    _.camelize(text)

class SnakeCase extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`HelloWorld` -> `hello_world`"
  displayName: 'Underscore _'
  hover: icon: ':snake-case:', emoji: ':snake:'
  getNewText: (text) ->
    _.underscore(text)

class PascalCase extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`hello_world` -> `HelloWorld`"
  displayName: 'Pascalize'
  hover: icon: ':pascal-case:', emoji: ':triangular_ruler:'
  getNewText: (text) ->
    _.capitalize(_.camelize(text))

class DashCase extends TransformString
  @extend()
  @registerToSelectList()
  displayName: 'Dasherize -'
  @description: "HelloWorld -> hello-world"
  hover: icon: ':dash-case:', emoji: ':dash:'
  getNewText: (text) ->
    _.dasherize(text)

class TitleCase extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`HelloWorld` -> `Hello World`"
  displayName: 'Titlize'
  getNewText: (text) ->
    _.humanizeEventName(_.dasherize(text))

class EncodeUriComponent extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`Hello World` -> `Hello%20World`"
  displayName: 'Encode URI Component %'
  hover: icon: 'encodeURI', emoji: 'encodeURI'
  getNewText: (text) ->
    encodeURIComponent(text)

class DecodeUriComponent extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`Hello%20World` -> `Hello World`"
  displayName: 'Decode URI Component %%'
  hover: icon: 'decodeURI', emoji: 'decodeURI'
  getNewText: (text) ->
    decodeURIComponent(text)

class TrimString extends TransformString
  @extend()
  @registerToSelectList()
  @description: "` hello ` -> `hello`"
  displayName: 'Trim string'
  getNewText: (text) ->
    text.trim()

class CompactSpaces extends TransformString
  @extend()
  @registerToSelectList()
  @description: "`  a    b    c` -> `a b c`"
  displayName: 'Compact space'
  getNewText: (text) ->
    if text.match(/^[ ]+$/)
      ' '
    else
      # Don't compact for leading and trailing white spaces.
      text.replace /^(\s*)(.*?)(\s*)$/gm, (m, leading, middle, trailing) ->
        leading + middle.split(/[ \t]+/).join(' ') + trailing

# -------------------------
class TransformStringByExternalCommand extends TransformString
  @extend(false)
  autoIndent: true
  command: '' # e.g. command: 'sort'
  args: [] # e.g args: ['-rn']
  stdoutBySelection: null

  execute: ->
    new Promise (resolve) =>
      @collect(resolve)
    .then =>
      super

  collect: (resolve) ->
    @stdoutBySelection = new Map
    unless @isMode('visual')
      @updateSelectionProperties() # [FIXME]
      @target.select()

    running = finished = 0
    for selection in @editor.getSelections()
      running++
      {command, args} = @getCommand(selection) ? {}
      if command? and args?
        do (selection) =>
          stdin = @getStdin(selection)
          stdout = (output) =>
            @stdoutBySelection.set(selection, output)
          exit = (code) ->
            finished++
            resolve() if (running is finished)

          @runExternalCommand {command, args, stdout, exit, stdin}
          @oldRestorePoint(selection) unless @isMode('visual')

  runExternalCommand: (options) ->
    {stdin} = options
    delete options.stdin
    bufferedProcess = new BufferedProcess(options)
    bufferedProcess.onWillThrowError ({error, handle}) =>
      # Suppress command not found error intentionally.
      if error.code is 'ENOENT' and error.syscall.indexOf('spawn') is 0
        commandName = @constructor.getCommandName()
        console.log "#{commandName}: Failed to spawn command #{error.path}."
      @cancelOperation()
      handle()

    if stdin
      bufferedProcess.process.stdin.write(stdin)
      bufferedProcess.process.stdin.end()

  getNewText: (text, selection) ->
    @getStdout(selection) ? text

  # For easily extend by vmp plugin.
  getCommand: (selection) ->
    {@command, @args}

  # For easily extend by vmp plugin.
  getStdin: (selection) ->
    selection.getText()

  # For easily extend by vmp plugin.
  getStdout: (selection) ->
    @stdoutBySelection.get(selection)

# -------------------------
selectListItems = null
class TransformStringBySelectList extends TransformString
  @extend()
  @description: "Interactively choose string transformation operator from select-list"
  requireInput: true

  getItems: ->
    selectListItems ?= transformerRegistry.map (klass) ->
      if klass::hasOwnProperty('displayName')
        displayName = klass::displayName
      else
        displayName = _.humanizeEventName(_.dasherize(klass.name))
      {name: klass, displayName}

  initialize: ->
    super

    @vimState.onDidConfirmSelectList (transformer) =>
      @vimState.reset()
      target = @target?.constructor.name
      @vimState.operationStack.run(transformer.name, {target})
    @focusSelectList({items: @getItems()})

  execute: ->
    # NEVER be executed since operationStack is replaced with selected transformer
    throw new Error("#{@getName()} should not be executed")

class TransformWordBySelectList extends TransformStringBySelectList
  @extend()
  target: "InnerWord"

class TransformSmartWordBySelectList extends TransformStringBySelectList
  @extend()
  @description: "Transform InnerSmartWord by `transform-string-by-select-list`"
  target: "InnerSmartWord"

# -------------------------
class ReplaceWithRegister extends TransformString
  @extend()
  @description: "Replace target with specified register value"
  hover: icon: ':replace-with-register:', emoji: ':pencil:'
  getNewText: (text) ->
    @vimState.register.getText()

# Save text to register before replace
class SwapWithRegister extends TransformString
  @extend()
  @description: "Swap register value with target"
  getNewText: (text, selection) ->
    newText = @vimState.register.getText()
    @setTextToRegister(text, selection)
    newText

# Indent < TransformString
# -------------------------
class Indent extends TransformString
  @extend()
  hover: icon: ':indent:', emoji: ':point_right:'
  stayOnLinewise: false
  indentFunction: "indentSelectedRows"

  onDidRestoreCursorPositions: ->
    unless @needStay()
      for cursor in @editor.getCursors()
        cursor.moveToFirstCharacterOfLine()

  mutateSelection: (selection) ->
    selection[@indentFunction]()

class Outdent extends Indent
  @extend()
  hover: icon: ':outdent:', emoji: ':point_left:'
  indentFunction: "outdentSelectedRows"

class AutoIndent extends Indent
  @extend()
  hover: icon: ':auto-indent:', emoji: ':open_hands:'
  indentFunction: "autoIndentSelectedRows"

class ToggleLineComments extends TransformString
  @extend()
  hover: icon: ':toggle-line-comments:', emoji: ':mute:'
  mutateSelection: (selection) ->
    selection.toggleLineComments()

# Surround < TransformString
# -------------------------
class Surround extends TransformString
  @extend()
  @description: "Surround target by specified character like `(`, `[`, `\"`"
  displayName: "Surround ()"
  pairs: [
    ['[', ']']
    ['(', ')']
    ['{', '}']
    ['<', '>']
  ]
  spaceSurroundedRegExp: /^\s([\s|\S]+)\s$/
  input: null
  charsMax: 1
  hover: icon: ':surround:', emoji: ':two_women_holding_hands:'
  requireInput: true
  autoIndent: false

  initialize: ->
    super

    return unless @requireInput
    @onDidConfirmInput (input) => @onConfirm(input)
    @onDidChangeInput (input) => @addHover(input)
    @onDidCancelInput => @cancelOperation()
    if @requireTarget
      @onDidSetTarget =>
        @vimState.input.focus({@charsMax})
    else
      @vimState.input.focus({@charsMax})

  onConfirm: (@input) ->
    @processOperation()

  getPair: (char) ->
    pair = _.detect(@pairs, (pair) -> char in pair)
    pair ?= [char, char]

  surround: (text, char, options={}) ->
    keepLayout = options.keepLayout ? false
    [open, close] = @getPair(char)
    if (not keepLayout) and LineEndingRegExp.test(text)
      @autoIndent = true # [FIXME]
      open += "\n"
      close += "\n"

    if char in settings.get('charactersToAddSpaceOnSurround') and isSingleLine(text)
      open + ' ' + text + ' ' + close
    else
      open + text + close

  getNewText: (text) ->
    @surround(text, @input)

class SurroundWord extends Surround
  @extend()
  @description: "Surround **word**"
  target: 'InnerWord'

class SurroundSmartWord extends Surround
  @extend()
  @description: "Surround **smart-word**"
  target: 'InnerSmartWord'

class MapSurround extends Surround
  @extend()
  @description: "Surround each word(`/\w+/`) within target"
  withOccurrence: true
  patternForOccurence: /\w+/g

class DeleteSurround extends Surround
  @extend()
  @description: "Delete specified surround character like `(`, `[`, `\"`"
  pairChars: ['[]', '()', '{}'].join('')
  requireTarget: false

  onConfirm: (@input) ->
    # FIXME: dont manage allowNextLine independently. Each Pair text-object can handle by themselvs.
    @setTarget @new 'Pair',
      pair: @getPair(@input)
      inner: false
      allowNextLine: (@input in @pairChars)
    @processOperation()

  getNewText: (text) ->
    text = text[1...-1]
    if isSingleLine(text)
      text.trim()
    else
      text

class DeleteSurroundAnyPair extends DeleteSurround
  @extend()
  @description: "Delete surround character by auto-detect paired char from cursor enclosed pair"
  requireInput: false
  target: 'AAnyPair'

class DeleteSurroundAnyPairAllowForwarding extends DeleteSurroundAnyPair
  @extend()
  @description: "Delete surround character by auto-detect paired char from cursor enclosed pair and forwarding pair within same line"
  target: 'AAnyPairAllowForwarding'

class ChangeSurround extends DeleteSurround
  @extend()
  @description: "Change surround character, specify both from and to pair char"
  charsMax: 2
  char: null

  onConfirm: (input) ->
    return unless input
    [from, @char] = input.split('')
    super(from)

  getNewText: (text) ->
    innerText = super # Delete surround
    @surround(innerText, @char, keepLayout: true)

class ChangeSurroundAnyPair extends ChangeSurround
  @extend()
  @description: "Change surround character, from char is auto-detected"
  charsMax: 1
  target: "AAnyPair"
  cursorPositions: null
  _restoreCursorPositions: null

  initialize: ->
    @onDidSetTarget =>
      @_restoreCursorPositions = saveCursorPositions(@editor)
      @target.select()
      unless haveSomeSelection(@editor)
        @vimState.input.cancel()
        @abort()
      @addHover(@editor.getSelectedText()[0])
    super

  onConfirm: (@char) ->
    # Clear pre-selected selection to start mutation from non-selection.
    @_restoreCursorPositions()
    @_restoreCursorPositions = null
    @input = @char
    @processOperation()

class ChangeSurroundAnyPairAllowForwarding extends ChangeSurroundAnyPair
  @extend()
  @description: "Change surround character, from char is auto-detected from enclosed and forwarding area"
  target: "AAnyPairAllowForwarding"

# Join < TransformString
# -------------------------
# FIXME
# Currently native editor.joinLines() is better for cursor position setting
# So I use native methods for a meanwhile.
class Join extends TransformString
  @extend()
  target: "MoveToRelativeLine"
  flashTarget: false

  needStay: -> false

  mutateSelection: (selection) ->
    if swrap(selection).isLinewise()
      range = selection.getBufferRange()
      selection.setBufferRange(range.translate([0, 0], [-1, Infinity]))
    selection.joinLines()
    end = selection.getBufferRange().end
    selection.cursor.setBufferPosition(end.translate([0, -1]))

class JoinWithKeepingSpace extends TransformString
  @extend()
  @registerToSelectList()
  input: ''
  requireTarget: false
  trim: false
  initialize: ->
    @setTarget @new("MoveToRelativeLineWithMinimum", {min: 1})

  mutateSelection: (selection) ->
    [startRow, endRow] = selection.getBufferRowRange()
    swrap(selection).expandOverLine()
    rows = for row in [startRow..endRow]
      text = @editor.lineTextForBufferRow(row)
      if @trim and row isnt startRow
        text.trimLeft()
      else
        text
    selection.insertText @join(rows) + "\n"

  join: (rows) ->
    rows.join(@input)

class JoinByInput extends JoinWithKeepingSpace
  @extend()
  @registerToSelectList()
  @description: "Transform multi-line to single-line by with specified separator character"
  hover: icon: ':join:', emoji: ':couple:'
  requireInput: true
  input: null
  trim: true
  initialize: ->
    super
    @focusInput(charsMax: 10)

  join: (rows) ->
    rows.join(" #{@input} ")

class JoinByInputWithKeepingSpace extends JoinByInput
  @description: "Join lines without padding space between each line"
  @extend()
  @registerToSelectList()
  trim: false
  join: (rows) ->
    rows.join(@input)

# -------------------------
# String suffix in name is to avoid confusion with 'split' window.
class SplitString extends TransformString
  @extend()
  @registerToSelectList()
  @description: "Split single-line into multi-line by splitting specified separator chars"
  hover: icon: ':split-string:', emoji: ':hocho:'
  requireInput: true
  input: null

  initialize: ->
    super
    unless @isMode('visual')
      @setTarget @new("MoveToRelativeLine", {min: 1})
    @focusInput(charsMax: 10)

  getNewText: (text) ->
    @input = "\\n" if @input is ''
    regex = ///#{_.escapeRegExp(@input)}///g
    text.split(regex).join("\n")

class ChangeOrder extends TransformString
  @extend(false)
  mutateSelection: (selection) ->
    swrap(selection).expandOverLine()
    textForRows = swrap(selection).lineTextForBufferRows()
    rows = @getNewRows(textForRows)
    newText = rows.join("\n") + "\n"
    selection.insertText(newText)

class Reverse extends ChangeOrder
  @extend()
  @registerToSelectList()
  @description: "Reverse lines(e.g reverse selected three line)"
  getNewRows: (rows) ->
    rows.reverse()

class Sort extends ChangeOrder
  @extend()
  @registerToSelectList()
  @description: "Sort lines alphabetically"
  getNewRows: (rows) ->
    rows.sort()
