require 'drb'
require 'net/http'
require 'net/http/persistent'
require 'date'
require 'timers'
require 'rexml/document'
include REXML  # so that we don't have to prefix everything with REXML::...

# check this out http://ruby-cookbook.wikispaces.com/distributed+ruby

# what a client does
#   Register with the server
#   Grab some credentials
#   Grab list of wants and witching hours
#   Start firing up timers
#
# timer state machine
#   If we're within a certian distance of witching time, speed up timer
#   start trying to register domains in sorted order
#     if the domain is taken, take it out of the list
#     if it is not yet for sale, keep at it
#     if you don't have enough $$$, ???

# TODO
#  add support for api limit errors

class NameCheaper
  class Error < StandardError
    attr_accessor :code

    # TODO: need to add subclasses that have error code set
    #       Note! some errors from namecheap seem to have multiple codes!
    #       perhaps a hash of codes to error classes?
    #
    #       see: http://blog.rubybestpractices.com/posts/gregory/anonymous_class_hacks.html
    #
    #
    #   goal:
    #    begin
    #     namecheaper.method()
    #    rescue IPLimitError
    #     something
    #    end
    #    rescue SomeOtherError
    #      something
    #    end
    #  end

  end

  attr_accessor :cred, :ip, :clockSkew

  def initialize(cred, ip)
    @cred = cred
    @ip = ip
    @uri = URI 'https://api.namecheap.com/xml.response'
    @http = Net::HTTP::Persistent.new 'drbsnipe'
    @commonParams = cred.to_hash
    @commonParams[:ClientIP] = ip
  end

  def getBalance
    response = callMethod('users.getBalances')
    balance = response.elements['UserGetBalancesResult'].attributes['AvailableBalance'].to_f
    puts "balance: #{balance}"
    return balance
  end

  def getTldList
    response = callMethod('domains.getTldList')
    tlds = {}
    response.elements['Tlds'].each_element do |tld|
      tlds[tld.attributes['Name']] = tld.attributes['IsApiRegisterable']
    end
    tlds.each_pair do |k,v|
      puts "tld #{k} #{v}"
    end
    return tlds
  end

  # TODO: make a create

  def pretendCreate(gtld)
    possibleResults = [:notOnSale, :Taken, :NotEnoughMoney, :BannedUser, :BannedIP]
  end

  # TODO: handle posts as well create is POST
  def callMethod(method, newParams = {})
    params = @commonParams.merge newParams
    params[:Command] = "namecheap." + method
    puts "calling #{method}"
    @uri.query = URI.encode_www_form(params)
    response = @http.request @uri
    findSkew(response)
    doc = Document.new response.body
    apiResponse = doc.elements['ApiResponse']
    status = apiResponse.attributes['Status']
    # FIXME: should probably throw here
    puts "not OK status: #{status}!" unless status == 'OK'
    errors = apiResponse.elements['Errors'].has_elements?
    puts "we have errors!" if errors
    return apiResponse.elements['CommandResponse']
  end

  def findSkew(response)
    servertime = DateTime.httpdate(response['DATE']).to_time
    now = Time.now
    @clockSkew = servertime - now
    puts "clockSkew: #{@clockSkew}"
  end

end

class Client
  include DRb::DRbUndumped

  attr_accessor :server, :ip, :state

  def initialize
    @timers = Timers.new
    uri = URI "http://curlmyip.com"
    @ip = Net::HTTP.get(uri)
    @state = :idle
  end

  def onTimerFire
    puts "timer fire!  state: #{@state}"
    gtld = @server.grabGtld
    # FIXME: factor server skew in here
    secondsUntil = ((gtld.startDate - DateTime.now) * 24 * 60 * 60).to_i
    if secondsUntil < 10
      # go into hyper mode

      #loop:
      # get a gtld
      # if result is domain is not on sale yet, keep trying
      # if result is domain is taken, put in taken list
      # if we don't have enough money, flip creds
      # if we've been banned using these creds, flip to new creds
      # if we've been banned from this IP, shutdown

      # unsolved problem: two or more gtlds go on sale.  We lose all
      # the races in one of them.  Some rolls of the loop, we get one
      # with no domains to grab.


    else
      # regular polling mode
      @namecheaper.getBalance
      @times.after(5) { onTimerFire }
    end
  end

  def onServerRegister(server)
    @server = server
    puts "client registered with server #{server}"
    creds = server.giveCreds
    puts "grabbed creds: #{creds} from server"

    @namecheaper = NameCheaper.new(creds, @ip)

    @state = :polling

    @timers.after(1) { onTimerFire }
#      puts "balance: #{@namecheaper.getBalance}"
#      @namecheaper.getBalance
#      @namecheaper.getTldList
#    end
    @thr = Thread.new { loop { @timers.wait } }
  end

  # write a method that figures out if we're to go into 'active' mode
  # or not

end

client = Client.new

DRb.start_service
server = DRbObject.new nil, 'druby://localhost:9000'

server.addClient client
DRb.thread.join
