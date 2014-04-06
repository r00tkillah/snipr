require 'drb'
require 'timers'

class NameCheapCreds
  include DRb::DRbUndumped

  attr_accessor :ApiUser, :ApiKey, :UserName

  def to_hash
    return {
      :ApiUser => @ApiUser,
      :ApiKey => @ApiKey,
      :UserName => @UserName
    }
  end
end

class GTld
  include DRb::DRbUndumped

  attr_accessor :tld, :startDate, :desiredDomains, :aquiredDomains

  def initialize(tld, startDate)
    @tld = tld
    @startDate = startDate
    @desiredDomains= []
    @aquiredDomains= []
    @takenDomains= []
  end

  def <=>(other)
    return @startDate<=>other.startDate
  end
end

class Server
  include DRb::DRbUndumped

  attr_accessor :creds
  attr_reader :gtlds

  def giveCreds
    self.creds[0]
  end

  def initialize
    @clients = []
    @creds = []
    @gtlds = []
# why do we need timers here?
#    @timers = Timers.new
#    @timer = @timers.every(5) do
#      puts "timer fired!"
#      @clients.each do |client|
#        #client.action("hi from timer")
#      end
#    end
#   @thr = Thread.new { loop { @timers.wait } }
  end

  def addClient(client)
    puts "new client \"#{client}\" connected"
    client.onServerRegister(self)
    @clients.push client
  end

  def addGtld(gtld)
    if @gtlds.empty?
      @gtlds << [gtld]
    else
      firstDate = @gtlds.first.first.startDate
      lastDate = @gtlds.last.first.startDate
      if gtld.startDate < firstDate
        @gtlds.unshift [gtld]
      elsif gtld.startDate > lastDate
        @gtlds.push [gtld]
      else
        @gtlds.each do |bucket|
          bucketStart = bucket.first.startDate
          start = gtld.startDate
          if bucket.first.startDate == gtld.startDate
            bucket.push gtld
            break
          end
          puts
        end
      end
    end
  end

  def grabGtld(date = DateTime.now)
    @gtlds.each do |bucket|
      if bucket.first.startDate > date
        return bucket.sample
      end
    end
  end

end


creds = NameCheapCreds.new
creds.ApiUser = 'YOUR USER NAME'
creds.ApiKey = 'YOUR API KEY'
creds.UserName = 'YOUR USER NAME'

training = GTld.new('training', (Time.now + 60).to_datetime)
training.desiredDomains = ['security', 'potty', 'cross']
mom = GTld.new('hacking', (Time.now + 60).to_datetime)
mom.desiredDomains = ['leet', 'uber']


server = Server.new
server.creds << creds
server.gtlds << training
server.gtlds << mom

DRb.start_service 'druby://localhost:9000', server
puts "Server running at #{DRb.uri}"

# the trap doensn't work right
#trap("INT") { puts "int" ; DRb.stop_service ; exit }
DRb.thread.join
