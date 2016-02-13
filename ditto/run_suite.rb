require 'liquid'
require 'securerandom'
require 'faraday'

URL = 'http://ditto.quantiguous.com'

X_QG_CI_SVC = ARGV[0]
VERBOSE = ARGV[1]

DELAY = 35

def load_steps
  p 'loading steps'
  return File.readlines(X_QG_CI_SVC + '.steps')
end


def set_headers(req, uri, delay)
   req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
   #req.headers['Accept'] = 'application/xml'
   req.headers['X-QG-CI-SVC'] = X_QG_CI_SVC
   unless uri.nil?
     req.headers['X-QG-CI-URI'] = uri
     req.headers['X-QG-CI-SCENARIO'] = 'SAD'
   end 
   unless delay.nil?
     req.headers['X-QG-CI-DELAY'] = delay.to_s
   end
end

def send_request(method, url, step = nil, delay = nil)
    conn = Faraday.new(:url => url, :ssl => {:verify => false}) do |c|
      c.use Faraday::Request::UrlEncoded
      c.use Faraday::Adapter::NetHttp
    end
    response = conn.send(method) do |req|
       set_headers(req, step, delay)
    end
    response
end

def run
  steps = load_steps

  steps.each do |step|
    method = step.split(',')[0].downcase
    uri = step.split(',')[1]
    uri = uri.gsub(/ |\n/,'')
    url = URL + uri
    
    # one happy request
    response = send_request(method, url)

    if response.status == 200 
       p "uri #{url} happy: ok"
    else
       p "uri #{url} happy: fail"
       p response unless VERBOSE.nil? 
    end 

    # one sad request per step
    response = send_request(method, url, uri)

    unless [200,404,501].include?(response.status)
       p "uri #{url} sad: ok"
    else
       p "uri #{url} sad: fail"
       p response unless VERBOSE.nil? 
    end 

    # one timeout request per step
    # send_request(method, url, uri, DELAY)
  end
end

run; nil
