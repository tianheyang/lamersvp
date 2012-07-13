#!/usr/bin/env ruby

require 'rubygems'
require 'redis'
require 'json'
require 'sinatra'
require 'sinatra/captcha'
require 'aws/ses'
require 'sanitize'
require 'haml'
require 'erb'

#set :port, 9999

REDIS = Redis.new
NEXT_EVENT = "20120726"
WAITING_LIST = "20120726-waitinglist"

# no limit at this event
RSVP_LIMIT = 110
CONTACT = "rsvp@js.la"

def rsvps_left()
  rsvps = REDIS.keys "#{NEXT_EVENT}*"
  RSVP_LIMIT - rsvps.length
end

def waitinglist_count()
  rsvps = REDIS.keys "#{WAITING_LIST}*"
  rsvps.length
end

def rsvp(redis_connection,user)
  REDIS.set "#{redis_connection}:#{user['email']}", user.to_json
end

def already_rsvpd(email)
  if REDIS.exists "#{NEXT_EVENT}:#{email}"
    return true
  else
    return false
  end
end

def delete(redis_connection,email)
  REDIS.del("#{redis_connection}:#{email}")
end

def get_auth(email)
  object = JSON.parse(REDIS.get "#{NEXT_EVENT}:#{email}")
  object["cancel"]
end

def send_email(email,string)
  ses = AWS::SES::Base.new(
    :access_key_id  => '',
    :secret_access_key => ''

  )
  # stick the user info into the subject instead of headers
  ses.send_email(
    :to => email,
    :from => CONTACT,
    :subject => "You've confirmed one seat for js.la on Thursday, July 26th, at 7pm",
    :body => "
Hi. Thanks for your RSVP for our July meetup in West Hollywood.  We're excited to see you.

We'll be meeting at CityGrid Media at 7pm, with talks starting around 7:20pm.

Their address is 8833 W. Sunset Boulevard West Hollywood, CA 90069

You can find a map and directions here: http://g.co/maps/bpc48
    
There is limited parking available at CityGrid, and once their lot is full they suggest using the West Hollywood Public Lot near Coffee Bean, just down the street from their office.  There is also plenty of metered parking on Sunset Blvd.

Should you need to cancel please visit http://js.la/cancel/#{string}

We update with speaker changes and info at http://js.la and http://twitter.com/LosAngelesJS

If you have any questions please feel free to reply to this email.

See you there!

the js.la team
"
  )
end

def send_waitinglist_email(email,string)
  ses = AWS::SES::Base.new(
    :access_key_id  => '',
    :secret_access_key => ''
  )
  # stick the user info into the subject instead of headers
  ses.send_email(
    :to => email,
    :from => CONTACT,
    :subject => "Thanks for getting on our #{NEXT_EVENT} waiting list",
    :body => "Hi there.  You're now on our waiting list for #{NEXT_EVENT}.

We'll email you if a seat becomes available.

If you have any questions, please feel free to reply to this email."

  )
end


# jacked from http://vitobotta.com/sinatra-contact-form-jekyll/
def valid_email?(email)
  if email =~ /^[a-zA-Z][\w\.-]*[a-zA-Z0-9]@[a-zA-Z0-9][\w\.-]*[a-zA-Z0-9]\.[a-zA-Z][a-zA-Z\.]*[a-zA-Z]$/
    domain = email.match(/\@(.+)/)[1]
    Resolv::DNS.open do |dns|
      @mx = dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
    end
    @mx.size > 0 ? true : false
  else
    false
  end
end
# /jacked

get '/rsvp' do
  @seats = rsvps_left
    puts "seats are #{@seats}"
  if @seats > 0
    @rsvps = RSVP_LIMIT - @seats
    erb :open
  else
    @seats = RSVP_LIMIT - @seats
    @waitinglist = waitinglist_count
    erb :waitinglist
  end
end

post '/rsvp' do
  if rsvps_left > 0 
    if captcha_pass?
      user = Hash.new
      params[:user].each do |k,v|
        user[k] = Sanitize.clean(v)
      end
      email = user["email"]
      user["cancel"] = rand(36**15).to_s(36)
      if valid_email?(email)
        unless already_rsvpd(email)
	  puts "rsvping"
          rsvp(NEXT_EVENT, user)
	  puts "sending email"
          send_email(email,user["cancel"])
	  puts "sent email"
	  @msg = "Thanks!  You have been confirmed for our July 26th event.  Check your email"
          erb :msg
        else
          @msg = "you are already rsvp'd for this event"
          erb :msg
        end
      else
        @msg = "your email looks fake.  are you a bot?"
        erb :msg
      end
    else
      @msg = "the captcha was wrong.  are you a bot?"
      erb :msg
    end
  else #someone is fucking with us
    erb :closed
  end
end

get '/cancel/:authstring' do |authstring|
  @seats = rsvps_left
  @authstring = authstring
  erb :confirm_cancel
end

post '/cancel/:authstring' do |authstring|
  email = params["email"]
  if already_rsvpd(email)
    if authstring == get_auth(email)
      delete(NEXT_EVENT,email)
      @msg = "You have canceled from our #{NEXT_EVENT} event"
    else
      @msg = "Sorry, I think this request is bogus.  Email us at #{CONTACT} to cancel"
    end
  else
    @msg = "Sorry, I do not know this email.  Email us at #{CONTACT} to cancel"
  end
  erb :msg
end

get '/rsvplist' do
  @rsvps = Hash.new
  list = REDIS.keys "#{NEXT_EVENT}*"
  list.each do |rsvp|
    @rsvps[rsvp] = JSON.parse(REDIS.get rsvp)
  end
  erb :list
end

