argv = require('optimist')
.usage '-t token  -s server -n team_name -p team_password'
.default 'n', 'fordan'
.default 'p', 'manoui'
.alias 't', 'token'
.alias 's', 'server'
.alias 'n', 'teamName'
.alias 'p', 'password'
.argv;


Tank = require './modules/tank'
logging = require('./modules/logging.coffee')

_ = require 'lodash'
cson = require 'cson'
zmq = require 'zmq'


class CommandChannel
  sock = zmq.socket 'req'
  screen0 = logging 0,4
  screen1 = logging 1,3
  constructor : (options) ->
    {@server, @token, @password, @teamName} = options
    sock.connect "tcp://#{@server}:5557"
    sock.on 'message', @handleMessage.bind @
    # do need this VERY FIRST/INITIAL connect when the match
    # hasn't started there wont be any sub data
    do @connect

  handleMessage : (data) ->
    data = JSON.parse data
    if data.comm_type is "MatchConnectResp"
      @client_token = data.client_token
      screen0 data
    else
      screen1 data

  connect : ->
    sock.send @MatchConnect()

  MatchConnect : ->
    JSON.stringify
      "comm_type" : "MatchConnect",
      "match_token" : @token,
      "team_name" : @teamName,
      "password" : @password

  send : (data) ->
    data.client_token = @client_token
    sock.send JSON.stringify data
    @

class StateChannel
  sock = zmq.socket 'sub'
  shouldInitialize = true
  screen2 = logging 2

  constructor : (options) ->
    {@server, @token, @password, @teamName} = options
    @commandChannel = new CommandChannel(options)
    sock.connect "tcp://#{@server}:5556"
    sock.on 'message', @handleMessage.bind @
    sock.subscribe(@token)

  initialize : (data) ->
    @commandChannel.connect()

    # index one isnt always the friendly team
    friendly = data.players[1]
    if friendly.name isnt @teamName
      friendly = data.players[0]

    screen2 friendly.name
    @tanks = {}
    for tank in friendly.tanks
      @tanks[tank.id] =  new Tank(tank)

    shouldInitialize = false
    return

  handleMessage : (token, state) ->
    data = JSON.parse state
    if data.comm_type isnt 'GAMESTATE'
      screen2 data

    if (data.comm_type is "GAME_END") or (data.comm_type is "GAME_START")
      shouldInitialize = true
      return

    if data.comm_type is "MatchEnd"
      process.exit 0

    if shouldInitialize
      return @initialize data


    if (data.comm_type is 'GAMESTATE')
      try
        for tank in data.players[1].tanks
          @tanks[tank.id].update tank
          @tanks[tank.id].handleMessage data.map,
            data.players[0].tanks,
            data.players[1].tanks,
            @commandChannel
      catch
        shouldInitialize = true
    return

SC = new StateChannel(argv)
