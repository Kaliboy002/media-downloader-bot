class Bot::Worker

  attr_reader :bot
  attr_reader :msg
  attr_reader :st

  attr_reader :dir
  attr_reader :opts

  delegate_missing_to :bot

  class_attribute :tmpdir
  self.tmpdir = ENV['TMPDIR'] || Dir.tmpdir

  def initialize bot, msg
    @bot = bot
    @msg = msg
  end

  def process
    Dir.mktmpdir "mdb-", tmpdir do |dir|
      @dir   = dir
      procs  = []
      inputs = []

      @st = Bot::Status.new do |text, *args, **params|
        text = me text unless params[:parse_mode]
        edit_message msg, msg.resp.message_id, *args, text: text, **params
      end

      popts = {dir:, bot:, msg:, st: @st}
      klass = if msg.audio.present? or msg.video.present? then Bot::FileProcessor else Bot::UrlProcessor end
      procs = msg.text.split("\n").flat_map do |l|
        klass.new line: l, **popts
      end

      msg.resp = send_message msg, me('Downloading metadata...')
      procs.each.with_index do |p, i|
        inputs[i] = p.download
      end
      inputs.flatten!

      @opts = inputs.first&.opts || SymMash.new
      inputs.sort_by!{ |i| i.info.title } if opts[:sort]
      inputs.reverse! if opts[:reverse]

      inputs.each.with_index.api_peach do |i, pos|
        @st.add "#{i.info.title}: downloading" do |stline|
          p = klass.new line: i.line, stline: stline, **popts

          p.download_one i, pos: pos+1 if p.respond_to? :download_one
          next if stline.error?

          stline.update "#{i.info.title}: converting"
          p.handle_input i, pos: pos+1
          next if stline.error?

          stline.update "#{i.info.title}: uploading"
          upload i

          p.cleanup
        end
      end

      return msg.resp = nil if inputs.blank?
    end
    msg.resp
  end

  def upload i
    oprobe = i.oprobe = Prober.for i.fn_out
    fn_out = i.fn_out
    type   = i.type
    info   = i.info
    durat  = i.oprobe.format.duration.to_i # speed may change from input
    opts   = i.opts

    caption = msg_caption i
    return send_message msg, caption if opts.simulate

    vstrea = oprobe&.streams&.find{ |s| s.codec_type == 'video' }

    thumb  = Faraday::UploadIO.new i.thumb, 'image/jpeg' if i.thumb

    fn_io   = Faraday::UploadIO.new fn_out, type.mime
    ret_msg = i.ret_msg = {
      type:        type.name,
      type.name => fn_io,
      duration:    durat,
      width:       vstrea&.width,
      height:      vstrea&.height,
      title:       info.title,
      performer:   info.uploader,
      thumb:       thumb,
      supports_streaming: true,
    }
    send_message msg, caption, **ret_msg
  end

  def msg_caption i
    return '' if opts.nocaption
    text = ''
    if opts.caption or i.type == Zipper::Types.video
      text  = "_#{me i.info.title}_"
      text << "\nby #{me i.info.uploader}" if i.info.uploader
    end
    text << "\n\n_#{me i.info.description.strip}_" if opts.description and i.info.description.strip.presence
    text << "\n\n#{me i.url}" if i.url
    text
  end

end

