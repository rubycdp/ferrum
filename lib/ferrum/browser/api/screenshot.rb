# frozen_string_literal: true

module Ferrum
  class Browser
    module API
      module Screenshot
        def screenshot(**opts)
          encoding, path, options = screenshot_options(**opts)

          data = if options[:format].to_s == "pdf"
            options = {}
            options[:paperWidth] = @paper_size[:width].to_f if @paper_size
            options[:paperHeight] = @paper_size[:height].to_f if @paper_size
            options[:scale] = @zoom_factor if @zoom_factor
            page.command("Page.printToPDF", **options)
          else
            page.command("Page.captureScreenshot", **options)
          end.fetch("data")

          return data if encoding == :base64

          bin = Base64.decode64(data)
          File.open(path.to_s, "wb") { |f| f.write(bin) }
        end

        def zoom_factor=(value)
          @zoom_factor = value.to_f
        end

        def paper_size=(value)
          @paper_size = value
        end

        private

        def screenshot_options(encoding: :base64, format: nil, path: nil, **opts)
          options = {}

          encoding = :binary if path

          if encoding == :binary && !path
            raise "Not supported option `:path` #{path}. Should be path to file"
          end

          format ||= path ? File.extname(path).delete(".") : "png"
          format = "jpeg" if format == "jpg"
          raise "Not supported options `:format` #{format}. jpeg | png | pdf" if format !~ /jpeg|png|pdf/i
          options.merge!(format: format)

          options.merge!(quality: opts[:quality] ? opts[:quality] : 75) if format == "jpeg"

          if !!opts[:full] && opts[:selector]
            warn "Ignoring :selector in #screenshot since full: true was given at #{caller(1..1).first}"
          end

          if !!opts[:full]
            width, height = page.evaluate("[document.documentElement.offsetWidth, document.documentElement.offsetHeight]")
            options.merge!(clip: { x: 0, y: 0, width: width, height: height, scale: @zoom_factor || 1.0 }) if width > 0 && height > 0
          elsif opts[:selector]
            rect = page.evaluate("document.querySelector('#{opts[:selector]}').getBoundingClientRect()")
            options.merge!(clip: { x: rect["x"], y: rect["y"], width: rect["width"], height: rect["height"], scale: @zoom_factor || 1.0 })
          end

          if @zoom_factor
            if !options[:clip]
              width, height = page.evaluate("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
              options[:clip] = { x: 0, y: 0, width: width, height: height }
            end

            options[:clip].merge!(scale: @zoom_factor)
          end

          [encoding, path, options]
        end
      end
    end
  end
end
