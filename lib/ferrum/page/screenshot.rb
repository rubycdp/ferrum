# frozen_string_literal: true

module Ferrum
  class Page
    module Screenshot
      DEFAULT_PDF_OPTIONS = {
        landscape: false,
        paper_width: 8.5,
        paper_height: 11,
        scale: 1.0
      }.freeze

      PAPEP_FORMATS = {
        letter:   { width:  8.50, height: 11.00 },
        legal:    { width:  8.50, height: 14.00 },
        tabloid:  { width: 11.00, height: 17.00 },
        ledger:   { width: 17.00, height: 11.00 },
        A0:       { width: 33.10, height: 46.80 },
        A1:       { width: 23.40, height: 33.10 },
        A2:       { width: 16.54, height: 23.40 },
        A3:       { width: 11.70, height: 16.54 },
        A4:       { width:  8.27, height: 11.70 },
        A5:       { width:  5.83, height:  8.27 },
        A6:       { width:  4.13, height:  5.83 },
      }.freeze

      def screenshot(**opts)
        path, encoding = common_options(**opts)
        options = screenshot_options(path, **opts)
        data = capture_screenshot(options, opts[:full])
        return data if encoding == :base64
        save_file(path, data)
      end

      def pdf(**opts)
        path, encoding = common_options(**opts)
        options = pdf_options(**opts).merge(transferMode: "ReturnAsStream")
        stream_handle = command("Page.printToPDF", **options).fetch("stream")
        if path
          stream_to_file(stream_handle, path)
        else
          stream_to_memory(stream_handle)
        end
      end

      def viewport_size
        evaluate <<~JS
          [window.innerWidth, window.innerHeight]
        JS
      end

      def document_size
        evaluate <<~JS
          [document.documentElement.scrollWidth,
           document.documentElement.scrollHeight]
        JS
      end

      private

      def save_file(path, data)
        bin = Base64.decode64(data)
        return bin unless path
        File.open(path.to_s, "wb") { |f| f.write(bin) }
      end

      def stream_to_file(stream_handle, path)
        File.open(path, 'wb') do |output_file|
          stream_to stream_handle, output_file
        end
      end

      def stream_to_memory(stream_handle)
        in_memory_data = ''
        stream_to stream_handle, in_memory_data
        in_memory_data
      end

      def stream_to(stream_handle, output)
        loop do
          read_result = command("IO.read", handle: stream_handle, size: 131072)
          data_chunk = read_result['data']
          data_chunk = Base64.decode64(data_chunk) if read_result['base64Encoded']
          output << data_chunk
          break if read_result['eof']
        end
      end

      def common_options(encoding: :base64, path: nil, **_)
        encoding = encoding.to_sym
        encoding = :binary if path
        [path, encoding]
      end

      def pdf_options(**opts)
        format = opts.delete(:format)
        options = DEFAULT_PDF_OPTIONS.merge(opts)

        if format
          if opts[:paper_width] || opts[:paper_height]
            raise ArgumentError, "Specify :format or :paper_width, :paper_height"
          end

          dimension = PAPEP_FORMATS.fetch(format)
          options.merge!(paper_width: dimension[:width],
                         paper_height: dimension[:height])
        end

        options.map { |k, v| [to_camel_case(k), v] }.to_h
      end

      def screenshot_options(path = nil, format: nil, scale: 1.0, **opts)
        options = {}

        format ||= path ? File.extname(path).delete(".") : "png"
        format = "jpeg" if format == "jpg"
        raise "Not supported options `:format` #{format}. jpeg | png" if format !~ /jpeg|png/i
        options.merge!(format: format)

        options.merge!(quality: opts[:quality] ? opts[:quality] : 75) if format == "jpeg"

        if !!opts[:full] && opts[:selector]
          warn "Ignoring :selector in #screenshot since full: true was given at #{caller(1..1).first}"
        end

        if !!opts[:full]
          width, height = document_size
          options.merge!(clip: { x: 0, y: 0, width: width, height: height, scale: scale }) if width > 0 && height > 0
        elsif opts[:selector]
          options.merge!(clip: get_bounding_rect(opts[:selector]).merge(scale: scale))
        end

        if scale != 1.0
          if !options[:clip]
            width, height = viewport_size
            options[:clip] = { x: 0, y: 0, width: width, height: height }
          end

          options[:clip].merge!(scale: scale)
        end

        options
      end

      def get_bounding_rect(selector)
        rect = evaluate_async(%Q(
          const rect = document
                         .querySelector('#{selector}')
                         .getBoundingClientRect();
          const {x, y, width, height} = rect;
          arguments[0]([x, y, width, height])
        ), timeout)

        { x: rect[0], y: rect[1], width: rect[2], height: rect[3] }
      end

      def to_camel_case(option)
        return :preferCSSPageSize if option == :prefer_css_page_size
        option.to_s.gsub(/(?:_|(\/))([a-z\d]*)/) { "#{$1}#{$2.capitalize}" }.to_sym
      end

      def capture_screenshot(options, full)
        maybe_resize_fullscreen(full) do
          command("Page.captureScreenshot", **options)
        end.fetch("data")
      end

      def maybe_resize_fullscreen(full)
        if full
          width, height = viewport_size.dup
          resize(fullscreen: true)
        end

        yield
      ensure
        resize(width: width, height: height) if full
      end
    end
  end
end
