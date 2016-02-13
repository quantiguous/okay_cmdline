require 'liquid'
require 'securerandom'
require 'faraday'


APPID = ARGV[2]
APPID = 'APP12' if APPID.nil? or APPID == ''
p APPID


SERVICE_NAME = ARGV[0]
OPERATION_NAME = ARGV[1]

URL = 'http://10.211.55.5:7080/' + SERVICE_NAME

FILE_NAME = SERVICE_NAME + '_' + OPERATION_NAME

DELAY = 35

BASIC_AUTH_USERNAME = ''
BASIC_AUTH_PASSWORD = ''

class UUID < Liquid::Tag
  def initialize(tag_name, max, tokens)
     super
     @max = max.to_i
  end

  def render(context)
    SecureRandom.uuid.gsub('-','').upcase
  end
end

Liquid::Template.register_tag('uuid', UUID)

def generate_urn
  return SecureRandom.uuid.gsub('-','').upcase
end

def load_template
  p 'loading template'
  return Liquid::Template.parse(File.read(FILE_NAME + '.template'))
end

def render_template(template)
  return template.render(
        {
            'appid' => APPID,
            'mobileNo' => Time.now.to_i 
        }
  )
end

def load_steps
  p 'loading steps'
  return File.readlines(FILE_NAME + '.steps')
end


def set_headers(req, uri, delay)
   req.headers['Content-Type'] = 'application/xml'
   req.headers['Accept'] = 'application/xml'
   req.headers['X-QG-CI-SVC'] = SERVICE_NAME
   unless uri.nil?
     req.headers['X-QG-CI-URI'] = uri
     req.headers['X-QG-CI-SCENARIO'] = 'SAD'
   end 
   unless delay.nil?
     req.headers['X-QG-CI-DELAY'] = delay.to_s
   end
end

def send_request(template, step = nil, delay = nil)
    conn = Faraday.new(:url => URL, :ssl => {:verify => false}) do |c|
      c.use Faraday::Request::UrlEncoded
      c.use Faraday::Request::BasicAuthentication, BASIC_AUTH_USERNAME, BASIC_AUTH_PASSWORD
      c.use Faraday::Response::Logger
      c.use Faraday::Adapter::NetHttp
    end
    response = conn.post do |req|
       set_headers(req, step, delay)

       req.body = template
    end
    p response.body
end

def run
  template = load_template
  uris = load_steps
  
  # one happy request
  send_request(render_template(template))

  uris.each do |uri|
    # one sad request per step
    send_request(render_template(template), uri)
  end
 
  uris.each do |uri|
    # one timeout request per step
    send_request(render_template(template), uri, DELAY)
  end
end

run
