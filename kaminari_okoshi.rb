require 'active_record'
require 'yaml'
require 'erb'

# ダミーデータ作成スクリプト
# スロークエリの検証用にまとまった数のデータが欲しくて作ったのでデータは完全ランダム
# ext/<table_name>.rb を作成してダミーデータをカスタムすることもできます
# 使い方:
#   ruby okosu <table_name> [--options]
#
# .e.g:
#   ruby okosu users -t 100 -s 10 -n 'kana,address', -u 'email,my_number', refs: "{ account_id: { table: 'accounts', column: 'id' }}"
class KaminariOkoshi
  attr_accessor :table, :total, :step, :uniqs, :nulls, :refs

  def self.run(table, total: 10000, step: 1000, uniqs: [], nulls: [], refs: {}, db: [:development, :primary] )
    set_ext(table)
    new(table, total.to_i, step.to_i, uniqs.map(&:to_sym), nulls.map(&:to_sym), refs, db.map(&:to_sym)).send(:make)
  end

  private

  # 拡張モジュールをprepend
  def self.set_ext(table)
    ext_path = File.join(File.expand_path(__dir__), 'ext', table + '.rb')
    if File.exists?(ext_path)
      basename = File.basename(ext_path, '.rb')
      require_relative 'ext/' + basename
      prepend basename.camelize.constantize
    end
  end

  def initialize(table_name, total, step, uniqs, nulls, refs, db)
    connect_to(db)
    abort "そんなテーブルは無い: #{table_name}" unless ActiveRecord::Base.connection.table_exists?(table_name)

    @table = model(table_name)
    @total = total
    @step  = step
    @nulls = nulls
    @max_msg_length = 0 # 進捗の最大文字列長

    set_uniqs(uniqs)
    set_refs(refs)
  end

  # db接続
  def connect_to(db)
    # use own config
    if File.exists?(File.join(__dir__, 'config', 'database.yml'))
      config = YAML.load(ERB.new(File.read(File.join(__dir__, 'config', 'database.yml'))).result, aliases: true, symbolize_names: true)
    else
      begin
        config = YAML.load(ERB.new(File.read(File.join(__dir__, '../', 'config', 'database.yml'))).result, aliases: true, symbolize_names: true)
      rescue ArgumentError
        # yaml(psych)のバージョン次第でaliaseが(デフォルトで)使えたり使えなかったり
        # とりあえず新しめで試してだめならaliases外してみる
        # https://qiita.com/scivola/items/da2e4687726fb20953c0
        config = YAML.load(ERB.new(File.read(File.join(__dir__, '../', 'config', 'database.yml'))).result, symbolize_names: true)
      end
    end

    # use rails
    database = config.dig(*db)

    ActiveRecord::Base.establish_connection(database)
  end

  # テーブル名からモデルクラスを定義
  def model(table_name)
    #Object.const_set(table_name.classify, Class.new(ActiveRecord::Base))
    # 名前がかぶるとどうなるかわからんので無名クラス
    Class.new(ActiveRecord::Base).tap do |ar_class|
      ar_class.table_name = table_name
    end
  end

  # unique制約リスト作成
  # uniqs:  [ 'xxx_id', 'yyy_code'... ]
  # @uniqs: { xxx_id: [1, 2, 3...], yyy_code: ['aaa', 'bbb', ...] }
  def set_uniqs(uniqs)
    @uniqs ||= {}
    uniqs.each do |column_name|
      @uniqs[column_name] = table.group(column_name).pluck(column_name)
    end
  end

  # 関連させたいカラムのサンプルリスト
  # refs:  { account_id: { table: 'accounts', column: 'id' } }
  # @refs: { account_id: [1,2,3...]
  def set_refs(refs)
    @refs ||= {}
    refs.each do |column_name, ref|
      ref = [:table, :column].zip(ref).to_h if ref.is_a?(Array)             # ex. ['accounts', 'id']
      ref = [:table, :column].zip(ref.split('.')).to_h if ref.is_a?(String) # ex. 'accounts.id'
      ref.symbolize_keys!
      @refs[column_name] = model(ref[:table]).select(ref[:column]).distinct.pluck(ref[:column])
    end
  end

  def sample_integer(_, _, limit)
    limit ||= 1
    # unsignedかどうかわからんので /2
    rand((("9"*limit).to_i/2))
  end

  def sample_float(_, _, limit)
    sample_integer(nil, nil, limit)
  end

  def sample_string(_, _, limit)
    quote(SecureRandom.hex[0...(limit || 1)])
  end

  def sample_boolean(_, _, _)
    [0, 1].sample
  end

  def sample_date(_, _, _)
    quote(rand(100.year.ago.to_date...Date.today))
  end

  def sample_text(_, _, limit)
    quote("text-" + sample_string(nil, nil, limit))
  end

  def sample_json(_, _, _)
    quote({}.to_json)
  end

  def sample_datetime(_, _, _)
    quote(rand(100.year.ago.to_datetime...Time.current.to_datetime).strftime("%Y-%m-%d %H:%M:%S"))
  end

  # dbの型に応じたランダム値を引く
  def sample_value(name, type, limit)
    send(['sample', type].join('_'), name, type, limit)
  end

  # unique指定されてる判定
  def unique?(name)
    (@unique_columns ||= @uniqs.keys).include?(name)
  end

  def retriable(*args, &block)
    retry_count = 0
    begin
      yield(*args)
    rescue
      disp "retry #{ [retry_count+=1, *args].join("/") }"
      retry
    end
  end

  # ユニーク値
  def unique_sample_value(name, type, limit)
    retriable(type, limit, name) do |type, limit, name|
      value = sample_value(name, type, limit)
      raise 'dup!' if @uniqs[name].include? value

      @uniqs[name] << value
      return value
    end
  end

  # 関連が指定されてる判定
  def ref?(name)
    (@ref_columns ||= @refs.keys).include?(name)
  end

  # 何かと関連
  def ref_sample_value(name, _, _)
    refs[name].sample
  end

  # int(11)とかから桁数を取り出す
  # ※column.limitから取りたいけど、integerはバイト数でややこしいのでヤメた
  # ※stringは文字列長
  # https://qiita.com/Yinaura/items/cede8324d08993d2065c
  def limit(column)
    ([(column.sql_type.match(/\d+/).to_s.presence || 10).to_i, 10].min) -1
  end

  # VALUESから除外する？
  def ignore?(column)
    # virtual, auto_increment, null指定なカラム は値を設定しない
    return true if column.auto_increment?
    return true if column.virtual?
    return true if nulls.include?(column.name.to_sym)

    false
  end

  # 標準出力
  def disp(msg)
    @max_msg_length = [@max_msg_length, msg.to_s.length].max
    print "\r#{msg}".ljust(@max_msg_length, " ")
  end

  # val -> 'val'
  def quote(val)
    "'#{escape(val)}'"
  end

  # don't -> don\'t
  def escape(val)
    val.to_s.gsub(/'/, "\\\\'")
  end

  def make
    # ダミーデータ入れるカラムリスト
    columns = table.columns.map do |c|
      next if ignore?(c)

      # to_symしておきたいだけ
      name, type, limit = c.name.to_sym, c.type.to_sym, limit(c)

      # 作成方法を決めとく
      [name, type, limit] << if respond_to?(name)
        name
      elsif unique?(name)
        :unique_sample_value
      elsif ref?(name)
        :ref_sample_value
      else
        :sample_value
      end
    end.compact

    # テンプレ
    query = <<~INSERT
      INSERT INTO #{table.table_name}(#{columns.map(&:first).join(', ')})
      VALUES %{values}
    INSERT

    progress = 0

    # 1000刻みが一番効率いいらしい
    # https://www.larajapan.com/2021/05/03/bulk-insertで大量のデータをdbに登録する/
    # > Array.new((125 / 20), 20) << (125 % 20) => [20, 20, 20, 20, 20, 20, 5]
    (Array.new((total / step), step) << (total % step)).reject(&:zero?).each do |i|
      progress += i
      values_list = i.times.map do
        "(#{
        columns.each.with_object([]) do |(name, type, limit, sender), values|
          values << send(sender, name, type, limit)
        end.join(', ')})"
      end
      disp progress # 進捗
      ActiveRecord::Base.transaction do
        table.connection.exec_query(query % { values: values_list.join(',') }) # INSERT
      end
      sleep 0.05 # 気休め
    end
  end
end
