module Cms
  module CompressionConfig
    # requires gems:
    # gem 'sass-rails', '~> 5.0'
    # gem 'uglifier'
    # gem "htmlcompressor"
    # gem 'rack-page_caching'
    # optional gems for image optimization
    # gem 'paperclip-optimizer'
    # gem 'image_optim'
    # gem 'image_optim_pack'
    # gem 'asset-image-opt'
    # gem 'sprockets-image_compressor'



    # use
    # in <PROJECT_ROOT>/config/initializers/cms.rb add:
    # Cms::CompressionConfig.initialize_compression

    def self.initialize_compression(options = {})
      # config/initializers/compression.rb
      f = Rails.root.join("config/production_config.rb")
      if File.exists?(f)
        require f
      end

      settings_applied = false

      settings = options.is_a?(Hash) ? options : {}


      if settings == false
        return
      end

      if settings == true
        settings = {}
      end

      settings[:enable_compression] = Rails.env.production? || !!ENV['ENABLE_COMPRESSION'] if settings[:enable_compression].nil?
      return if !settings[:enable_compression]

      defaults = {
          caching: true,
          compile: true,
          precompile: true,
          gzip: true,
          deflate: true,
          debug: true,
          js_compress: true,
          css_compress: false,
          html_compress: true
      }

      settings = defaults.merge(settings)


      Rails.application.configure do

        # Use environment names or environment variables:

        settings_applied = true

        # Strip all comments from JavaScript files, even copyright notices.
        # By doing so, you are legally required to acknowledge
        # the use of the software somewhere in your Web site or app:
        uglifier = settings[:js_compressor] || Uglifier.new(output: { comments: :none })

        # To keep all comments instead or only keep copyright notices (the default):
        # uglifier = Uglifier.new output: { comments: :all }
        # uglifier = Uglifier.new output: { comments: :copyright }

        config.assets.compile = settings[:compile]
        config.assets.debug = false

        if settings[:js_compress]
          config.assets.js_compressor = uglifier
        end

        if settings[:css_compress]
          config.assets.css_compressor = :sass
        end

        if settings[:deflate]
          config.middleware.use Rack::Deflater
          #config.middleware.insert Rack::Deflater
        end



        if settings[:html_compress]
          config.middleware.use HtmlCompressor::Rack,
                                compress_css: settings[:css_compress],
                                compress_javascript: true,
                                css_compressor: Sass,
                                enabled: true,
                                javascript_compressor: uglifier,
                                preserve_line_breaks: false,
                                remove_comments: true,
                                remove_form_attributes: false,
                                remove_http_protocol: false,
                                remove_https_protocol: false,
                                remove_input_attributes: true,
                                remove_intertag_spaces: false,
                                remove_javascript_protocol: true,
                                remove_link_attributes: true,
                                remove_multi_spaces: true,
                                remove_quotes: true,
                                remove_script_attributes: true,
                                remove_style_attributes: true,
                                simple_boolean_attributes: true,
                                simple_doctype: false
        end



        # caching
        if settings[:caching]
          config.middleware.use Rack::PageCaching,
                                # Directory where the pages are stored. Defaults to the public folder in
                                # Rails, but you'll probably want to customize this
                                page_cache_directory: Rails.public_path,
                                # Gzipped version of the files are generated with compression level
                                # specified. It accepts the symbol versions of the constants in Zlib,
                                # e.g. :best_speed and :best_compression. To turn off gzip, pass in false.
                                gzip: :best_speed,
                                # Hostnames can be included in the path of the page cache. Default is false.
                                include_hostname: false
        end
      end
    end
  end
end