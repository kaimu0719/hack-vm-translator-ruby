class CodeWriter
  C_PUSH = :C_PUSH
  C_POP = :C_POP

  # 書き込み用のファイルを生成する
  def initialize(vm_file_path)
    @output_file = File.open(vm_file_path.sub(/\.vm\z/, ".asm"), "w")
    @label_seq = 0
    @file_basename = File.basename(vm_file_path, ".vm")
  end

  # pushまたはpopコマンドのとき、VMコードに応じだアセンブリコードを書き込む
  def write_push_pop(command:, segment:, index:)
    case command
    when C_PUSH
      emit write_push(segment:, index:)
    when C_POP
      emit write_pop(segment:, index:)
    end
  end

  def write_arithmetic(command)
    case command
    when "add"
      emit write_add
    when "sub"
      emit write_sub
    when "neg"
      emit write_neg
    when "eq"
      emit write_eq
    when "gt"
      emit write_gt
    when "lt"
      emit write_lt
    when "and"
      emit write_and
    when "or"
      emit write_or
    when "not"
      emit write_not
    end
  end

  # label コマンド
  def write_label(label)
    emit <<~ASM
      (#{scope_label(label)})
    ASM
  end

  # if-goto コマンド
  # @SP                     SPのアドレスを指定
  # AM=M-1                  SPが指定しているアドレスを-1してAレジスタとメモリに格納する
  # D=M                     SPから-1したアドレスのメモリの値をDレジスタに格納する
  # @#{scope_label(label)}  指定されたラベルのアドレスを指定する
  # D;JNE                   Dレジスタの値が0じゃない場合は上記で指定されたアドレスにジャンプする
  def write_if(label)
    emit <<~ASM
      @SP
      AM=M-1
      D=M
      @#{scope_label(label)}
      D;JNE
    ASM
  end

  # goto コマンド
  # @#{scope_label(label)}  指定されたラベルのアドレスを指定する
  # 上記の指定されたアドレスに無条件ジャンプ
  def write_goto(label)
    emit <<~ASM
      @#{scope_label(label)}
      0;JMP
    ASM
  end

  # function コマンド
  # function <name> <nLocals>
  # 1) (<name>)というラベルを出力
  # 2) local を nLocals 個ぶん 0 で初期化(push constant 0 を n 回)
  def write_function(name, n_locals)
    num = n_locals.to_i

    emit <<~ASM
      (#{name})
    ASM

    num.times do
      emit write_constant index: 0
    end
  end

  # return コマンド
  # FRAME = LCL
  # RET   = *(FRAME - 5)
  # *ARG  = pop()
  # SP    = ARG + 1
  # THAT  = *(FRAME - 1)
  # THIS  = *(FRAME - 2)
  # ARG   = *(FRAME - 3)
  # LCL   = *(FRAME - 4)
  # goto RET
  def write_return
    emit <<~ASM
      @LCL
      D=M
      @R13
      M=D

      @5
      A=D-A
      D=M
      @R14
      M=D

      @SP
      AM=M-1
      D=M
      @ARG
      A=M
      M=D

      @ARG
      D=M+1
      @SP
      M=D

      @R13
      AM=M-1
      D=M
      @THAT
      M=D

      @R13
      AM=M-1
      D=M
      @THIS
      M=D

      @R13
      AM=M-1
      D=M
      @ARG
      M=D

      @R13
      AM=M-1
      D=M
      @LCL
      M=D

      @R14
      A=M
      0;JMP
    ASM
  end

  def close
    emit infinite_loop
    @output_file.close unless @output_file.closed?
  end

  private

    def unique_label(prefix)
      label = "#{prefix}$#{@label_seq}"
      @label_seq += 1
      label
    end

    def scope_label(label)
      "#{@file_basename}$#{label}"
    end

    def emit(asm)
      @output_file.write(asm)
    end

    def write_push(segment:, index:)
      case segment
      when "constant"
        write_constant(index:)
      when "local"
        write_push_from_base(base_symbol: "LCL", index:)
      when "argument"
        write_push_from_base(base_symbol: "ARG", index:)
      when "this"
        write_push_from_base(base_symbol: "THIS", index:)
      when "that"
        write_push_from_base(base_symbol: "THAT", index:)
      when "temp"
        write_push_temp(index:)
      when "pointer"
        write_push_pointer(index:)
      when "static"
        write_push_static(index:)
      end
    end

    def write_pop(segment:, index:)
      case segment
      when "local"
        write_pop_from_base(base_symbol: "LCL", index:)
      when "argument"
        write_pop_from_base(base_symbol: "ARG", index:)
      when "this"
        write_pop_from_base(base_symbol: "THIS", index:)
      when "that"
        write_pop_from_base(base_symbol: "THAT", index:)
      when "temp"
        write_pop_temp(index:)
      when "pointer"
        write_pop_pointer(index:)
      when "static"
        write_pop_static(index:)
      end
    end

    # push (base + index)
    # @#{base_symbol} ベースシンボルのアドレスを指定する
    # D=M             BSのRAMの値をDレジスタに格納する
    # @#{index}       indexアドレスを指定
    # A=D+A           BSのアドレスのRAMの値とindexを足した値をAレジスタに格納
    # D=M             指定したアドレスのRAMの値をDレジスタに格納
    # @SP             SPのアドレスを指定
    # A=M             SPのRAMの値をアドレスに指定する
    # M=D             BSに格納されているアドレスとindexの値を足したRAMの値をSPが指定しているRAMの値に格納
    # @SP             SPのアドレスを指定
    # M=M+1           SPの指定先のアドレスを+1にする
    def write_push_from_base(base_symbol:, index:)
      <<~ASM
        @#{base_symbol}
        D=M
        @#{index}
        A=D+A
        D=M
        @SP
        A=M
        M=D
        @SP
        M=M+1
      ASM
    end

    # pop -> *(base + index)
    # 1) (base+index) を R13 に退避
    # 2) stack pop を D に入れる
    # 3) *R13 = D
    # @#{base_symbol} ベースシンボルのアドレスを指定する
    # D=M             BSのRAMの値をDレジスタに格納する
    # @#{index}       indexのアドレスを指定する
    # D=D+A           index+baseの値をDレジスタの値に格納する
    # @R13            R13のアドレスを指定
    # M=D             (base+index)の値の合計をR13のメモリに格納する
    #
    # @SP             SPのアドレスを指定
    # AM=M-1          SPのメモリを-1してその値をAレジスタとSPのメモリに格納
    # D=M             SPのアドレスを-1したアドレスのメモリの値をDレジスタに格納
    # @R13            R13のレジスタを指定
    # A=M             R13のメモリの値をAレジスタに指定(*R13)
    # M=D             R13のポインタ(R13のメモリの値をアドレスとしたメモリ)にDレジスタの値(SPのメモリの値を-1したアドレスのメモリから取り出した値)を格納
    def write_pop_from_base(base_symbol:, index:)
      <<~ASM
        @#{base_symbol}
        D=M
        @#{index}
        D=D+A
        @R13
        M=D
        @SP
        AM=M-1
        D=M
        @R13
        A=M
        M=D
      ASM
    end

    # RAMの位置5~12に直接マッピングされる
    # @#{addr} temp iで(5+i)のアドレスを指定
    # D=M      先ほど指定したアドレスのメモリの値をDレジスタに格納
    # @SP      SPの値を指定
    # A=M      SPのメモリの値をAレジスタに格納
    # M=D      temp iで指定したメモリのRAMの値をSPが指定しているRAMに格納
    # @SP      SPのアドレスを指定
    # M=M+1    SPのRAMの値を+1にする
    def write_push_temp(index:)
      addr = 5 + index.to_i

      <<~ASM
        @#{addr}
        D=M
        @SP
        A=M
        M=D
        @SP
        M=M+1
      ASM
    end

    # RAMの位置5~12に直接マッピングされる
    # @SP      SPのアドレスを指定
    # AM=M-1   SPのメモリの値を-1してAレジスタとメモリに格納
    # D=M      SPのメモリの値をDレジスタに格納
    # @#{addr} temp iで(5+i)のアドレスを指定
    # M=D      先ほど指定したアドレスのメモリにSPのデータを格納
    def write_pop_temp(index:)
      addr = 5 + index.to_i

      <<~ASM
        @SP
        AM=M-1
        D=M
        @#{addr}
        M=D
      ASM
    end

    # THIS/THAT の値をスタックに push
    # @#{symbol} THIS or THATのアドレスを指定
    # D=M        上記で指定したメモリの値をDレジスタに格納
    # @SP        SPのアドレスを指定
    # A=M        SPのメモリの値をAレジスタに格納
    # M=D        SPが指定しているRAMに@#{symbol}で指定した値を格納
    # @SP        SPのアドレスを指定
    # M=M+1      SP++
    def write_push_pointer(index:)
      symbol = pointer_symbol(index)

      <<~ASM
        @#{symbol}
        D=M
        @SP
        A=M
        M=D
        @SP
        M=M+1
      ASM
    end

    # スタックの値を THIS/THAT のRAMに pop
    # @SP        SPのアドレスを指定
    # AM=M-1     SPのメモリの値を-1してAレジスタとSPのメモリに格納
    # D=M        SPのメモリの値をDレジスタに格納
    # @#{symbol} THIS or THATのアドレスを指定
    # M=D        SPから取り出した値を上記で指定したアドレスのメモリに格納
    def write_pop_pointer(index:)
      symbol = pointer_symbol(index)

      <<~ASM
        @SP
        AM=M-1
        D=M
        @#{symbol}
        M=D
      ASM
    end

    # THIS/THAT セグメントを選択する
    def pointer_symbol(index)
      case index.to_i
      when 0
        "THIS"
      when 1
        "THAT"
      end
    end

    # push static i: static iで指定した値をスタックにpushする
    # @#{symbol} staticシンボルのアドレスを指定
    # D=M        上記で指定したメモリの値をDレジスタに格納
    # @SP        スタックポインタのアドレスを指定
    # A=M        上記で指定したメモリの値をAレジスタに格納
    # M=D        上記で指定したメモリにstaticシンボルのRAMのデータを格納
    # @SP        SPのアドレスを指定
    # M=M+1      SP++
    def write_push_static(index:)
      symbol = static_symbol(index)

      <<~ASM
        @#{symbol}
        D=M
        @SP
        A=M
        M=D
        @SP
        M=M+1
      ASM
    end

    # pop static i: スタックの値をstatic iで指定したアドレスにpopする
    # @SP        SPのアドレスを指定
    # AM=M-1     SPのメモリの値を-1してAレジスタとSPのメモリに格納
    # D=M        --SPのメモリの値をDレジスタに格納
    # @#{symbol} シンボルのアドレスを指定する
    # M=D        SPの値をシンボルのメモリに格納
    def write_pop_static(index:)
      symbol = static_symbol(index)

      <<~ASM
        @SP
        AM=M-1
        D=M
        @#{symbol}
        M=D
      ASM
    end

    # staticシンボル名の作成
    def static_symbol(index)
      "#{@file_basename}.#{index}"
    end

    # メモリセグメント: constant
    # constant i の定数iをpushする。
    #
    # @{i}  constant i で指定されたiのアドレスを指定する
    # D=A   Dレジスタに定数iの値を書き込む
    # @SP   スタックポインタのアドレス[0]を指定する
    # A=M   スタックポインタのRAMの値をAレジスタに格納する 
    # M=D   指定したアドレスのRAMにDレジスタの値(定数i)を書き込む
    # @SP   スタックポインタのアドレスを再度指定する
    # M=M+1 スタックポインタのRAMの値を+1する
    def write_constant(index:)
      <<~ASM
        @#{index}
        D=A
        @SP
        A=M
        M=D
        @SP
        M=M+1
      ASM
    end

    # 整数の加算: x + y
    # @SP    スタックポインタのアドレスを指定(yのアドレスの+1のアドレスを指定している)
    # AM=M-1 スタックポインタのアドレスのRAMの値を-1してそれをアドレスレジスタとスタックポインタのRAMに書き込む(yのアドレスを指定してそれをSPとAレジスタに保存)
    # D=M    スタックポインタのRAMの値をデータレジスタに書き込む（Dレジスタにyの値を保存する）
    # @SP    スタックポインタのアドレス[0]を指定する
    # A=M-1  スタックポインタのRAMの値を-1した値(これがxのアドレス値)をアドレスレジスタに書き込む(SPのRAMの値を-1することでxのアドレスを指定することができる)
    # M=D+M  データレジスタの値とRAMの値を加算してRAMに書き込む(xのアドレスのRAMの値をDレジスタの値yを加算してxのアドレスのRAMに値を書き込む)
    def write_add
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        M=D+M
      ASM
    end

    # 整数の減算: x - y
    def write_sub
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        M=M-D
      ASM
    end

    # 符号反転（2の補数）: -y
    def write_neg
      <<~ASM
        @SP
        A=M-1
        M=-M
      ASM
    end

    # 等しい: x == y
    # @SP       SPのアドレスを指定(yのアドレスの+1のアドレスを指定している)
    # AM=M-1    SPのアドレス[0]のRAMの値を-1してそれをAレジスタとSPのRAMに書き込む(yのアドレスを指定してそのアドレスをSPのRAMとAレジスタに保存)
    # D=M       yのRAMの値をDレジスタに格納する
    # @SP       SPのアドレスを再指定(先ほどはyのAレジスタを指定していたので、それをSPのアドレス指定[0]に戻す)
    # A=M-1     SPのRAMの値を-1して、それをAレジスタに格納する(これによってAレジスタはxのアドレスを指定していることになる)
    # D=M-D     xのアドレスのRAMの値とDレジスタの値(これはyの値)の差を出してDレジスタに格納する(x-y)
    # @EQ_TRUE  EQ_TRUEというシンボル定数のアドレスを指定する(これはシンボルテーブルに格納されているアドレスが指定されている)
    # D;JEQ     x-yの値が0だった場合にEQ_TRUEのアドレスにジャンプする
    # 
    # @SP       --- (x-y)の値が0じゃない場合, SPのアドレスを指定 ---
    # A=M-1     SPのRAMの値を-1してAレジスタに格納する(これによってAレジスタはxのアドレスを指定していることになる)
    # M=0       xのRAMの値を0に指定する(これで x == y が false であることが表現できる)
    # @EQ_END   EQ_ENDのアドレスを指定する
    # 0;JMP     無条件ジャンプ EQ_ENDアドレスにジャンプする
    #
    # (EQ_TRUE) EQ_TRUEのラベルを宣言する。これによりEQ_TRUEのアドレスが指定されたときにジャンプしてくる
    # @SP       SPのアドレスを指定
    # A=M-1     xのアドレスを指定
    # M=-1      xのアドレスのRAMの値を-1にする(これで x == y が true であることが表現できる)
    #
    # (EQ_END)  EQ_ENDのラベルを宣言する。これによりEQ_ENDのアドレスが指定されたときにジャンプしてくる
    def write_eq
      true_label = unique_label("EQ_TRUE")
      end_label  = unique_label("EQ_END")
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        D=M-D
        @#{true_label}
        D;JEQ

        @SP
        A=M-1
        M=0
        @#{end_label}
        0;JMP

        (#{true_label})
        @SP
        A=M-1
        M=-1

        (#{end_label})
      ASM
    end

    # ~より小さい(less than): x < y
    # @SP       SPのアドレスを指定
    # AM=M-1    SPのRAMの値を-1してRAMとAレジスタに値を格納する
    # D=M       yのRAMの値をDレジスタに格納する
    # @SP       SPのアドレスを指定
    # A=M-1     SPのRAMの値を-1してAレジスタに格納する
    # D=M-D     (x - y)の計算を行い結果をDレジスタに格納する
    # @LT_TRUE  LT_TRUEのアドレスを指定する
    # D;JLT     D < 0 だったらLT_TRUEのアドレスにジャンプする
    #
    # @SP       SPのアドレスを指定
    # A=M-1     yのアドレスを指定
    # M=0       yのRAMに0を指定する(これによって x < y が false であることが表現できる)
    # @LT_END   LT_ENDのアドレスを指定する
    # 0;JMP     LT_ENDのアドレスに無条件ジャンプする
    #
    # (LT_TRUE) LT_TRUEのラベル宣言をしてLT_TRUEのジャンプ先のアドレスを指定する
    # @SP       SPのアドレスを指定
    # A=M-1     yのアドレスを指定
    # M=-1      yのRAMに-1を格納する(これによって x < y が true であることを表現できる)
    #
    # (LT_END)  LT_ENDのラベル宣言をしてLT_ENDのジャンプ先のアドレスを指定する
    def write_lt
      true_label = unique_label("LT_TRUE")
      end_label  = unique_label("LT_END")
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        D=M-D
        @#{true_label}
        D;JLT

        @SP
        A=M-1
        M=0
        @#{end_label}
        0;JMP

        (#{true_label})
        @SP
        A=M-1
        M=-1

        (#{end_label})
      ASM
    end

    # ~より大きい(Greater than): x > y
    def write_gt
      true_label = unique_label("GT_TRUE")
      end_label  = unique_label("GT_END")
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        D=M-D
        @#{true_label}
        D;JGT

        @SP
        A=M-1
        M=0
        @#{end_label}
        0;JMP
        
        (#{true_label})
        @SP
        A=M-1
        M=-1

        (#{end_label})
      ASM
    end

    # ビット単位And: x And y
    def write_and
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        M=D&M
      ASM
    end

    # ビット単位Or: x Or y
    def write_or
      <<~ASM
        @SP
        AM=M-1
        D=M
        @SP
        A=M-1
        M=D|M
      ASM
    end

    # ビット単位Not: Not y
    def write_not
      <<~ASM
        @SP
        A=M-1
        M=!M
      ASM
    end

    def infinite_loop
      <<~ASM
        (END)
        @END
        0;JMP
      ASM
    end
end