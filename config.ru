# frozen_string_literal: true

require 'sinatra'

require 'json'
require 'yaml'
require 'securerandom'
require 'base64'
require 'net/http'
require 'uri'
require 'erb'

ENV['WORKSHOP_URL'] = 'https://raw.githubusercontent.com/marekjelen/starter-guides/master/_workshops/java.yml'

class Datastore

  class << self

    def load_content
      return @data if @data
      @data = {}
      ENV.each_pair do |name, value|
        next unless name.start_with?('WORKSHOP_URL')
        uri = URI.parse(value)
        data = YAML.load(Net::HTTP.get_response(uri).body)
        @data[data['id']] = data
      end
      @data
    end

    def plans
      return @plans if @plans
      load_content
      @plans = []
      i = 0
      @data.each_pair do |id, workshop|
        plan = {
          id: '00000000-0000-0000-0000-00000000000' + (i += 1).to_s,
          name: id,
          description: workshop['name'],
          free: true,
          bindable: false,
          metadata: {
            bullets: []
          },
          schemas: {
            service_instance: {
              create: {
                parameters: {
                  '$schema' => 'http://json-schema.org/draft-04/schema#',
                  type: 'object',
                  properties: {}
                }
              }
            }
          }
        }

        p = plan[:schemas][:service_instance][:create][:parameters][:properties]
        workshop['vars'].each_pair do |name, value|
          p[name] = {
            type: 'string',
            description: value
          }
        end

        @plans << plan
      end
    end

    def services
      [{
         name: 'workshops',
         id: '00000000-0000-0000-0000-000000000000',
         bindable: false,
         plan_updateable: false,
         description: 'Workshop content as a service',
         metadata: {
           provider: {
             name: 'Workshopper',
             listing: {
               imageUrl: '',
               blurb: 'Workshop content as a service',
               longDescription: 'Easily deploy your workshop content'
             }
           }
         },
         plans: plans
       }]
    end

  end

end

class Servicebroker < Sinatra::Base

  helpers do

    def k8s_request(verb, path, data = nil)
      token = File.read('/var/run/secrets/kubernetes.io/serviceaccount/token')
      verb = verb.to_s.downcase.capitalize
      request = Net::HTTP.const_get(verb).new(path)
      request['Authorization'] = "Bearer #{token}"
      request['Accept'] = 'application/json'
      request['Content-Type'] = 'application/json'
      request['Connection'] = 'close'
      request.body = data
      http = Net::HTTP.new(ENV['KUBERNETES_SERVICE_HOST'], ENV['KUBERNETES_SERVICE_PORT'])
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.request(request)
    end

  end

  get '/v2/catalog' do
    {
      services: Datastore.services
    }.to_json
  end

  get '/v2/service_instances/:instance_id/last_operation' do
    @id = params['instance_id']
    @operation = params['operation']

    if @operation.start_with?('create')
      response = k8s_request('GET', '/oapi/v1/namespaces/myproject/deploymentconfigs')
      if response.code == '200'
        data = JSON.load(response.body)
        dc = data['items'].find {|it| it['metadata']['labels']['id'] == @id}
        if dc && dc['status']['availableReplicas'] == dc['status']['replicas']
          {
            state: 'succeeded',
            description: 'Workshop content is deployed.'
          }.to_json
        else
          {
            state: 'in progress',
            description: 'Still deploying the workshop content.'
          }.to_json
        end
      else
        {
          state: 'failed',
          description: 'Failed deploying the workshop content.'
        }.to_json
      end
    elsif @operation.start_with?('destroy')
      response = k8s_request('GET', '/oapi/v1/namespaces/myproject/deploymentconfigs')
      if response.code == '200'
        data = JSON.load(response.body)
        dc = data['items'].find {|it| it['metadata']['labels']['id'] == @id}
        if dc
          {
            state: 'in progress',
            description: 'Still undeploying the workshop content.'
          }.to_json
        else
          {
            state: 'succeeded',
            description: 'Workshop content is undeployed.'
          }.to_json
        end
      else
        {
          state: 'failed',
          description: 'Failed undeploying the workshop content.'
        }.to_json
      end
    end
  end

  # "{\"service_id\":\"00000000-0000-0000-0000-000000000000\",\"plan_id\":\"00000000-0000-0000-0000-000000000001\",\"organization_guid\":\"576d9e0b-3c28-11e8-bcc0-f689af18b742\",\"space_guid\":\"576d9e0b-3c28-11e8-bcc0-f689af18b742\",\"parameters\":{\"name\":\"dfvsdvsdfv\"},\"context\":{\"namespace\":\"myproject\",\"platform\":\"kubernetes\"}}"

  put '/v2/service_instances/:instance_id' do
    @id = params['instance_id']
    @name = 'sample'
    @data = JSON.load(request.body.read)

    dc = {
      apiVersion: 'v1',
      kind: 'DeploymentConfig',
      metadata: {
        name: @name,
        labels: {
          id: @id
        }
      },
      spec: {
        replicas: 1,
        selector: {
          id: @id
        },
        strategy: {},
        triggers: [{type: 'ConfigChange'}],
        template: {
          metadata: {
            labels: {
              id: @id
            }
          },
          spec: {
            containers: [{
                           image: 'osevg/workshopper:latest',
                           imagePullPolicy: 'Always',
                           name: @name,
                           ports: [{containerPort: 8080, protocol: 'TCP'}]
                         }]
          }
        }
      }
    }.to_json

    response = k8s_request('POST', '/oapi/v1/namespaces/myproject/deploymentconfigs', dc)
    puts response.code.inspect
    puts response.body.inspect

    status 202
    {
      operation: "create_#{@instance}"
    }.to_json
  end

  delete '/v2/service_instances/:instance_id' do
    @plan = params['plan_id']
    @service = params['service_id']
    @id = params['instance_id']

    response = k8s_request('DELETE', '/oapi/v1/namespaces/myproject/deploymentconfigs/sample', '{}')
    response = k8s_request('DELETE', "/api/v1/namespaces/myproject/replicationcontrollers?labelSelector=id%3D#{@id}", '{}')
    response = k8s_request('DELETE', "/api/v1/namespaces/myproject/pods?labelSelector=id%3D#{@id}", '{}')
    puts response.code.inspect
    puts response.body.inspect

    status 202
    {
      operation: "destroy_#{@instance}"
    }.to_json
  end

  patch '/v2/service_instances/:instance_id' do
    status 404
    {}.to_json
  end

  put '/v2/service_instances/:instance_id/service_bindings/:binding_id' do
    status 404
    {}.to_json
  end

  delete '/v2/service_instances/:instance_id/service_bindings/:binding_id' do
    status 404
    {}.to_json
  end

end

run Servicebroker
