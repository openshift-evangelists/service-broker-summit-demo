# frozen_string_literal: true

module K8s

  class << self

    DCS = '/oapi/v1/namespaces/%s/deploymentconfigs'
    PODS = '/api/v1/namespaces/%s/pods'
    RCS = '/api/v1/namespaces/%s/replicationcontrollers'
    SVCS = '/api/v1/namespaces/%s/services'

    def client
      addr = ENV['KUBERNETES_SERVICE_HOST']
      port = ENV['KUBERNETES_SERVICE_PORT']

      client = Net::HTTP.new(addr, port)
      client.use_ssl = true
      client.verify_mode = OpenSSL::SSL::VERIFY_NONE
      client
    end

    def request(verb, path, data = nil)
      token = File.read('/var/run/secrets/kubernetes.io/serviceaccount/token')
      verb = verb.to_s.downcase.capitalize

      puts "#{verb} #{path}"

      request = Net::HTTP.const_get(verb).new(path)
      request['Authorization'] = "Bearer #{token}"
      request['Accept'] = 'application/json'
      request['Content-Type'] = 'application/json'
      request['Connection'] = 'close'
      request.body = data if data

      response = client.request(request)

      puts response.code
      puts response.body

      response
    end

    def deploy(project, id, env = {})
      env = env.keys.inject([]) do |data, name|
        data << { name: name, value: env[name] }
        data
      end

      container = {
        image: 'osevg/workshopper:latest',
        imagePullPolicy: 'Always',
        name: 'main',
        env: env,
        ports: [{ containerPort: 8080, protocol: 'TCP' }]
      }

      dc = {
        apiVersion: 'v1',
        kind: 'DeploymentConfig',
        metadata: {
          name: 'workshop',
          labels: {
            id: id
          }
        },
        spec: {
          replicas: 1,
          selector: {
            id: id
          },
          strategy: {},
          triggers: [{ type: 'ConfigChange' }],
          template: {
            metadata: {
              labels: {
                id: id
              }
            },
            spec: {
              containers: [container]
            }
          }
        }
      }

      svc = {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
          name: 'workshop',
          labels: {
            id: id
          }
        },
        spec: {
          selector: {
            id: id
          },
          ports: [{ port: 8080, protocol: 'TCP', targetPort: 8080 }]
        }
      }

      request('POST', DCS % project, dc.to_json)
      request('POST', SVCS % project, svc.to_json)
    end

    def deployed?(project, id)
      response = request('GET', DCS % project)
      if response.code == '200'
        data = JSON.load(response.body)
        dc = data['items'].find { |it| it['metadata']['labels']['id'] == id }

        if dc && dc['status']['availableReplicas'] == dc['status']['replicas']
          :deployed
        else
          :in_progress
        end
      else
        raise StandardError, "HTTP response code #{response.code}"
      end
    end

    def undeploy(project, id)
      selector = "?labelSelector=id%3D#{id}"
      empty = {}.to_json

      request('DELETE', (DCS % project) + selector, empty)
      request('DELETE', (RCS % project) + selector, empty)
      request('DELETE', (PODS % project) + selector, empty)
    end

    def undeployed?(project, id)
      response = request('GET', DCS % project)
      if response.code == '200'
        data = JSON.load(response.body)
        dc = data['items'].find { |it| it['metadata']['labels']['id'] == @id }
        if dc
          :in_progress
        else
          :undeployed
        end
      else
        raise StandardError, "HTTP response code #{response.code}"
      end
    end

  end

end