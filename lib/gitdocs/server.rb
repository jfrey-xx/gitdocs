require 'thin'
require 'renee'
require 'coderay'

module Gitdocs
  class Server
    def initialize(config, *gitdocs)
      @config = config
      @gitdocs = gitdocs
    end

    def start(port = 8888)
      gds = @gitdocs
      conf = @config
      Thin::Server.start('127.0.0.1', port) do
        use Rack::Static, :urls => ['/css', '/js', '/img', '/doc'], :root => File.expand_path("../public", __FILE__)
        run Renee {
          if request.path_info == '/'
            render! "home", :layout => 'app', :locals => {:gds => gds}
          else
            path 'settings' do
              get.render! 'settings', :layout => 'app', :locals => {:conf => conf}
              post do
                shares = conf.shares
                request.POST['share'].each do |idx, share|
                  shares[Integer(idx)].update_attributes(share)
                end
                redirect! '/settings'
              end
            end

            var :int do |idx|
              gd = gds[idx]
              halt 404 if gd.nil?
              file_path = request.path_info
              file_path = request.path_info.gsub('/save', '') if save_file = request.path_info =~ %r{/save$}
              file_path = request.path_info.gsub('/upload', '') if upload_file = request.path_info =~ %r{/upload$}
              file_ext  = File.extname(file_path)
              expanded_path = File.expand_path(".#{file_path}", gd.root)
              halt 400 unless expanded_path[/^#{Regexp.quote(gd.root)}/]
              parent = File.dirname(file_path)
              parent = '' if parent == '/'
              parent = nil if parent == '.'
              locals = {:idx => idx, :parent => parent, :root => gd.root, :file_path => expanded_path}
              mode, mime = request.params['mode'], `file -I #{expanded_path}`.strip
              if save_file # Saving
                File.open(expanded_path, 'w') { |f| f.print request.params['data'] }
                redirect! "/" + idx.to_s + file_path
              elsif upload_file # Uploading
                halt 404 unless file = request.params['file']
                tempfile, filename = file[:tempfile], file[:filename]
                FileUtils.mv(tempfile.path, File.expand_path(filename, expanded_path))
                redirect! "/" + idx.to_s + file_path + "/" + filename
              elsif !File.exist?(expanded_path) # edit for non-existent file
                render! "edit", :layout => 'app', :locals => locals.merge(:contents => "")
              elsif File.directory?(expanded_path)
                contents = Dir[File.join(gd.root, request.path_info, '*')]
                render! "dir", :layout => 'app', :locals => locals.merge(:contents => contents)
              elsif mode == 'delete' # delete file
                FileUtils.rm(expanded_path)
                redirect! "/" + idx.to_s + parent
              elsif mode == 'edit' && mime.match(%r{text/}) # edit file
                contents = File.read(expanded_path)
                render! "edit", :layout => 'app', :locals => locals.merge(:contents => contents)
              elsif mode != 'raw' && mime.match(%r{text/}) # render file
                begin # attempting to render file
                  contents = '<div class="tilt">'  + Tilt.new(expanded_path).render + '</div>'
                rescue RuntimeError => e # not tilt supported
                  contents = '<pre class="CodeRay">' + CodeRay.scan_file(expanded_path).encode(:html) + '</pre>'
                end
                render! "file", :layout => 'app', :locals => locals.merge(:contents => contents)
              else # other file
                run! Rack::File.new(gd.root)
              end
            end
          end
        }.setup {
          views_path File.expand_path("../views", __FILE__)
        }
      end
    end
  end
end