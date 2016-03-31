require 'liquid'
require 'securerandom'
require 'faraday'
require 'nokogiri'
require 'oga'
require 'active_support/all'
require 'oj'
require 'json'
require 'open-uri'

APPID = ARGV[4]
APPID = 'APP12' if APPID.nil? or APPID == ''
p APPID

STEP_NO = ARGV[0].to_i
SERVICE_NAME = ARGV[1]
OPERATION_NAME = ARGV[2]
SERVICE_KIND = ARGV[3]

SOAP_URL = 'http://10.211.55.6:7080/' + SERVICE_NAME
JSON_URL = 'http://10.211.55.6:7080/Worklight/' + SERVICE_NAME.split('Service').first + 'MobileService/' + OPERATION_NAME 

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
            'emailID' => Time.now.to_i.to_s + '@gmail.com'
        }
  )
end

def remove_soap_header(xmlDoc)
  xsl_string = '<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:soapenv12="http://www.w3.org/2003/05/soap-envelope" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"><xsl:template match="@* | node()"><xsl:copy><xsl:apply-templates select="@* | node()" /></xsl:copy></xsl:template><xsl:template match="soapenv:*"><xsl:apply-templates select="@* | node()" /></xsl:template><xsl:template match="soapenv12:*"><xsl:apply-templates select="@* | node()" /></xsl:template></xsl:stylesheet>'
  xsl_template = Nokogiri::XSLT(xsl_string)
  return xsl_template.transform(xmlDoc)    
end

def is_valid_as_per_schema(xmlString)
  xmlDoc = Nokogiri::XML(xmlString)
  ns = xmlDoc.xpath('/*').first.namespace.prefix
  
  if xmlDoc.xpath("/#{ns}:Envelope/#{ns}:Body/#{ns}:Fault").count > 0 
    # we have a fault, no validation
    return true
  else
    # we have a success
    strippedDoc = remove_soap_header(xmlDoc)
    xsd = load_schema
    return xsd.validate(strippedDoc).empty?
  end  
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
    if SERVICE_KIND == 'SOAP'
      url = SOAP_URL 
    else 
      url = JSON_URL 
    end

    conn = Faraday.new(:url => url, :ssl => {:verify => false}) do |c|
      c.use Faraday::Request::UrlEncoded
      c.use Faraday::Request::BasicAuthentication, BASIC_AUTH_USERNAME, BASIC_AUTH_PASSWORD
      c.use Faraday::Response::Logger
      c.use Faraday::Adapter::NetHttp
    end
    response = conn.post do |req|
       set_headers(req, step, delay, step_no)

       req.body = template
       puts template
    end
    respStr = response.body
    
   # puts "Schema Validation : #{is_valid_as_per_schema(respStr)}" if SERVICE_KIND == 'SOAP'
    # puts "\e[5m Schema validation : #{is_valid_as_per_schema(respStr) } \e[0m" if SERVICE_KIND == 'SOAP'
    puts respStr
end

def build_request(template)
  if SERVICE_KIND == 'SOAP'
    request = render_template(template)
  else
    xml_obj = Oga.parse_xml(render_template(template)).to_xml
    json_request = Hash.from_xml(xml_obj)
    request = json_request['Envelope']['Body'].to_json
  end
end

def load_schema
  url = "https://api.github.com/repos/quantiguous/iib3/contents/#{SERVICE_NAME}/#{SERVICE_NAME}_InlineSchema1.xsd?ref=master&access_token=#{ENV['GITHUB_PERSONAL_TOKEN']}"
  p url
  x = Faraday.get(url)
  y = JSON.parse(x.body)
  return Nokogiri::XML::Schema(Base64.decode64(y["content"]))
end

def run
  template = load_template
  steps = load_steps
    
  # only happy request
  if STEP_NO == -1
     send_request(build_request(template))
     return
  end

  if STEP_NO == 0
     # one happy request
     send_request(build_request(template))

     steps.each_with_index do |step, index|
       # one sad request per step
       send_request(build_request(template), step, nil)
       # one timeout request per step
       send_request(build_request(template), step, DELAY, index+1)
     end

     return
  end

  # array indexes start from 0
  i = STEP_NO - 1
  # one sad request
  send_request(build_request(template), steps[i], nil)
  # one delay request
  send_request(build_request(template), steps[i], DELAY, STEP_NO)
end

run