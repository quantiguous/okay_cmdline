require 'liquid'
require 'securerandom'
require 'faraday'
require 'equivalent-xml'
require 'nokogiri'

URL = 'https://uatsky.yesbank.in:7081/V3/flexcube'

API_UNDER_TEST = ARGV[0]

DELAY = 35

BASIC_AUTH_USERNAME = 'testclient'
BASIC_AUTH_PASSWORD = 'test@123'

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
  return Liquid::Template.parse(File.read(API_UNDER_TEST + '.template'))
end

def render_template(template)
  return template.render
end



def set_headers(req, query)
   req.headers['Content-Type'] = 'application/xml'
   req.headers['Accept'] = 'application/xml'
   unless query.nil?
     req.headers['X-QG-FLEXPROXY-USE-QUERY'] = 'allowed'
   end 
end

def send_request(template, query = nil)
    conn = Faraday.new(:url => URL, :ssl => {:verify => false}) do |c|
      c.use Faraday::Request::UrlEncoded
      c.use Faraday::Request::BasicAuthentication, BASIC_AUTH_USERNAME, BASIC_AUTH_PASSWORD
      c.use Faraday::Response::Logger
      c.use Faraday::Adapter::NetHttp
    end
    response = conn.post do |req|
       set_headers(req, query)

       req.body = template
    end
    return response.body
end

def run
  template = load_template
  
  # one request without query
  rep1 = send_request(render_template(template))

  # one request with query
  rep2 = send_request(render_template(template), true)

  node_1 = Nokogiri::XML(rep1)
  node_2 = Nokogiri::XML(rep2)

  if EquivalentXml.equivalent?(node_1, node_2, opts = { :element_order => true }) == true 
    p 'matched'
  else
    p 'not mached'
    p rep1
    p rep2
  end

  return
end

run
