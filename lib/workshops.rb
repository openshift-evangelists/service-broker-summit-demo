# frozen_string_literal: true

module Workshops

  class << self

    if [ENV['RAILS_ENV'], ENV['RACK_ENV']].include?('development')
      ENV['WORKSHOP_URL'] = 'https://raw.githubusercontent.com/marekjelen/starter-guides/master/_workshops/java.yml'
      ENV['WORKSHOP_URL_2'] = 'https://raw.githubusercontent.com/openshift-labs/custom-service-broker-workshop/master/_workshop.yml'
    end

    def content
      return @data if @data
      @data = {}
      i = 0
      ENV.each_pair do |name, value|
        next unless name.start_with?('WORKSHOP_URL')
        uri = URI.parse(value)
        data = YAML.load(Net::HTTP.get_response(uri).body)
        data['__url'] = value
        id = '00000000-0000-0000-0000-00000000000' + (i += 1).to_s
        @data[id] = data
      end
      @data
    end

    def plans
      return @plans if @plans
      @plans = []
      content.each_pair do |id, workshop|
        plan = {
          id: id,
          name: workshop['id'],
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
      {
        services: [{
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
      }
    end

  end

end