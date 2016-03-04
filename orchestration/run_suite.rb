require 'liquid'
require 'securerandom'
require 'faraday'


APPID = ARGV[3]
APPID = 'APP12' if APPID.nil? or APPID == ''
p APPID


STEP_NO = ARGV[0].to_i
SERVICE_NAME = ARGV[1]
OPERATION_NAME = ARGV[2]

URL = 'http://10.211.55.5:7080/' + SERVICE_NAME

FILE_NAME = SERVICE_NAME + '_' + OPERATION_NAME

DELAY = 32

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
            'mobileNo' => Time.now.to_i,
            'idDocumentNo' => Time.now.to_i,
            'emailID' => Time.now.to_i.to_s + '@quantiguous.com'
        }
  )
end

def load_steps
  p 'loading steps'
  return File.readlines(FILE_NAME + '.steps')
end


def set_headers(req, uri, delay, step_no)
   req.headers['Content-Type'] = 'application/xml'
   req.headers['Accept'] = 'application/xml'
   req.headers['X-QG-CI-SVC'] = SERVICE_NAME
   unless uri.nil?
     req.headers['X-QG-CI-URI'] = uri
     req.headers['X-QG-CI-SCENARIO'] = 'SAD'
   end 
   unless delay.nil?
     req.headers['X-QG-CI-DELAY'] = delay.to_s
     req.headers['X-QG-CI-DELAY-STEP'] = step_no.to_s
   end
end

def send_request(template, step = nil, delay = nil, step_no = nil)
    conn = Faraday.new(:url => URL, :ssl => {:verify => false}) do |c|
      c.use Faraday::Request::UrlEncoded
      c.use Faraday::Request::BasicAuthentication, BASIC_AUTH_USERNAME, BASIC_AUTH_PASSWORD
      c.use Faraday::Response::Logger
      c.use Faraday::Adapter::NetHttp
    end
    response = conn.post do |req|
       set_headers(req, step, delay, step_no)

       req.body = template
    end
    p response.body
end

def run
  template = load_template
  steps = load_steps
  # only happy request
  if STEP_NO == -1
     send_request(render_template(template))
     return
  end

  if STEP_NO == 0
     # one happy request
     send_request(render_template(template))
  
     steps.each_with_index do |step, index|
       # one sad request per step
       send_request(render_template(template), step, nil)
     end
 
     steps.each_with_index do |step, index|
       # one timeout request per step
       send_request(render_template(template), step, DELAY, index+1)
     end

     return
  end

  # array indexes start from 0
  i = STEP_NO - 1
  # one sad request
  send_request(render_template(template), steps[i], nil)
  # one delay request
  send_request(render_template(template), steps[i], DELAY, STEP_NO)
end

run
