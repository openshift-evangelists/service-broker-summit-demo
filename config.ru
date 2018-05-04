# frozen_string_literal: true

require_relative 'lib/common'

class Servicebroker < Sinatra::Base

  CACHE = {}

  get '/v2/catalog' do
    Workshops.services.to_json
  end

  get '/v2/service_instances/:instance_id/last_operation' do
    @id = params['instance_id']
    @operation = params['operation']

    begin
      if @operation.start_with?('create')
        if K8s.deployed?(CACHE[@id], @id)
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
      elsif @operation.start_with?('destroy')
        if K8s.undeployed?(CACHE[@id], @id)
          {
            state: 'succeeded',
            description: 'Workshop content is undeployed.'
          }.to_json
        else
          {
            state: 'in progress',
            description: 'Still undeploying the workshop content.'
          }.to_json
        end
      end
    rescue => e
      {
        state: 'failed',
        description: "Operation failed: #{e.message}"
      }.to_json
    end
  end

  put '/v2/service_instances/:instance_id' do
    @id = params['instance_id']
    @data = JSON.load(request.body.read)
    puts @data.inspect
    @plan = @data['plan_id']
    @parameters =
    @context = @data['context']

    CACHE[@id] = { namespace: @context['namespace'] }

    env = (@data['parameters'] || {}).merge({
      'WORKSHOPS_URLS' => Workshops.content[@plan]['__url']
    })

    K8s.deploy(@context['namespace'], @id, env)

    status 202

    { operation: "create_#{@id}" }.to_json
  end

  delete '/v2/service_instances/:instance_id' do
    @id = params['instance_id']

    K8s.undeploy(CACHE[@id][:namespace], @id)

    status 202

    { operation: "destroy_#{@id}" }.to_json
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