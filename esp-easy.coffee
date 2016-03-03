module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  fs = require 'fs'
  _ = env.require 'lodash'
  http = require 'http'

  cie1931 = []

  fs.readFile "/home/pi/pimatic-app/node_modules/pimatic-esp-easy/cie1931.txt", (err, data) ->
    throw err if err
    cie1931 = data.toString().split("\, ")

  linear = (_.range(0, 1023, 1))
  #console.log linear

  class ESPEasyPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("ESPEasyDimmer", {
        configDef: deviceConfigDef.ESPEasyDimmer,
        createCallback: (config) ->
          device = new ESPEasyDimmer(config)
          return device
      })

  class ESPEasyDimmer extends env.devices.DimmerActuator

    constructor: (@config, lastState) ->
      @id = config.id
      @name = config.name
      @gpio = config.gpio
      @mode = config.mode
      @correction = config.correction
      @delay = (config.delay / 10)
      if config.lastDimlevel?
        @_dimlevel = config.lastDimlevel or 0
      @_state = off
      if @_dimlevel > 0
        @_state = on
        if @correction is "cie1931"
          writeCommand @gpio + "," + (i for i, index in cie1931 when index == @_dimlevel * 10)
        if @correction is "linear"
          writeCommand @gpio + "," + (@_dimlevel * 10)
      super()

    changeDimlevelTo: (dimlevel) ->
      if @_dimlevel is dimlevel then return 
      else
        actlevel = @_dimlevel * 10
        level = dimlevel * 10
        if @config.mode is "skip"
          if @config.correction is "linear"
            writeCommand @gpio + "," + (level)
            #console.log level
          if @config.correction is "cie1931"
            writeCommand @gpio + "=" + (i for i, index in cie1931 when index == level)
        else if @config.mode is "dim"
          if @config.correction is "cie1931"
            if @_dimlevel < dimlevel
              slice = cie1931.slice(actlevel, level)
              @_pwm(slice, @gpio, @delay)
            if @_dimlevel > dimlevel
              slice = cie1931.slice(level, actlevel).reverse()
              @_pwm(slice, @gpio, @delay)
          else if @config.correction is "linear"
            if @_dimlevel < dimlevel
              slice = linear.slice(actlevel, level)
              @_pwm(slice, @gpio, @delay)
            if @_dimlevel > dimlevel
              slice = linear.slice(level, actlevel).reverse()
              @_pwm(slice, @gpio, @delay)
          else
            env.logger.error("Error pwm on #{@config.name}")
        @_setDimlevel dimlevel
      return Promise.resolve()

    _setDimlevel: (dimlevel) ->
      super dimlevel
      @config.lastDimlevel = dimlevel
      plugin.framework.saveConfig()

    writeCommand = (arr) ->
      console.log arr
      #http.get { hostname: '10.0.0.60', port: 80, path: '/control?cmd=PWM,0,#{@arr}' }, (res) ->
      http.get "http://10.0.0.60/control?cmd=PWM" + "," + (arr), (res) ->
        console.log res.req.path
      return

    _pwm: (arr, gpio, delay) ->
      loop_ = (i) ->
        setTimeout (->
          #console.log arr[i]
          writeCommand arr[i]
          loop_ i + 1  if i < arr.length - 1
          return
        ), delay
      loop_ 0

  plugin = new ESPEasyPlugin

  return plugin
