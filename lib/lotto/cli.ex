defmodule Lotto.CLI do
  @moduledoc """
  Lotto Number Generator (ver: #{Mix.Project.config[:version]})

  synopsis:
    Generate Lotto numbers from frequency tables
  usage:
    $ lotto {options} file
    $ lotto --scrape url
  options:
    --least           Use least frequently selected numbers (defaults to true)
    --most            Use most frequently selected numbers (defaults to false)
    --select=S        Number of Lotto numbers to select (defaults to 6)
    --count=C         Number of frequency numbers to draw from (defaults to 8)
    --scrape          Scrape the URL provided and dump [numb,freq] in CSV format
  where:
    file  Comma-separated CSV file of the form:

          # datafile.csv
          number, frequency
          1, 345
          2, 340
          ...

    url   URL containing list of lotto numbers with frequencies
  """

  require Logger

  
  def main(), do: main([])
  def main(args) do
    args |> parse |> validate |> process 
  end
  

  @option_parser_switches [select: :integer, count: :integer, most: :boolean, least: :boolean, scrape: :boolean]
  defp parse(args) do
    options  = %{select: 6, count: 8, most: false, least: false, scrape: false}
    switches = @option_parser_switches
    aliases  = [h: :help, m: :most, l: :least, s: :select, c: :count]
    parse    = OptionParser.parse(args, switches: switches, aliases: aliases)

    case parse do
      { [help: true], _, _   } -> :help
      { [], args, []         } -> {options, args}
      { opts, args, []       } -> {Enum.into(opts, options), args}
      { opts, args, bad_opts } -> {Enum.into(merge_opts(opts, bad_opts), options), args}
      _                        -> {:help, args}
    end
  end
  defp merge_opts(opts, bad_opts) do
    bad_opts |> rehabilitate_args |> Keyword.merge(opts)
  end
  defp rehabilitate_args(bad_args) do
    bad_args
    |> Enum.flat_map(fn x -> Tuple.to_list(x) end)
    |> Enum.filter(fn str -> str end)
    |> Enum.map(fn str -> String.replace(str, ~r/^\-([^-]+)/, "--\\1") end)
    |> OptionParser.parse(switches: @option_parser_switches)
    |> Tuple.to_list
    |> List.first 
  end


  defp validate(:help) do
    IO.puts(@moduledoc)
  end 
  # defp validate({:help, bad_args}) do
  #   error("unknown option(s): #{bad_args}")
  # end
  defp validate({options, args}) do
    %{
      least:    options.least or !options.most,     # default least: true unless most is set when least isn't
      most:     !(options.least or !options.most),  # most is just ! of least 
      select:   options.select,
      count:    max(options.select, options.count),
      scrape:   options.scrape,
      source:   Enum.at(args, 0)
    }
  end


  # Do nothing
  defp process(:ok), do: :ok

  # Fail with error if no input file specified
  defp process(%{ least: _, most: _, select: _, count: _, scrape: false, source: nil} = _opts) do
    error("no input specified")
  end

  # Scrape the provided URL and dump as CSV to :stdout
  defp process(%{ least: _, most: _, select: _, count: _, scrape: true, source: url} = _opts) do
    url
    |> Lotto.Scraper.scrape_frequencies_from
    |> Lotto.Scraper.dump_csv
  end

  # Read from file and generate game combos.
  defp process(opts) do
    freq   = (if (opts.least), do: "least", else: "most") <> " frequent"
    listfn = (if (opts.least), do: &Lotto.Frequencies.infrequent_list/2, else: &Lotto.Frequencies.frequent_list/2)

    nmbrs =
      opts.source
      |> Lotto.Frequencies.data_from_filename()

    uniqs =
      nmbrs
      |> listfn.(opts.count)

    games =
      uniqs
      |> Lotto.Combos.combo(opts.select)

    output(%{ opts: opts, freq: freq, nmbrs: nmbrs, uniqs: uniqs, games: games})
  end

  # Dump output in a nice format. 
  defp output(%{ opts: opts, freq: freq, nmbrs: _nmbrs, uniqs: uniqs, games: games}) do
    IO.puts "Processing: '#{opts.source}', selecting: #{opts.select} numbers from #{opts.count} #{freq} numbers "

    IO.write "#{Enum.count(games)} game(s) generated using: ["
    for {uniq, _k} <- Enum.with_index(uniqs |> Enum.intersperse(", ")) do
      IO.write if (uniq == ", "), do: uniq, else: String.pad_leading("#{uniq}", 2, " ")
    end
    IO.puts "]"

    for {game, i} <- Enum.with_index(games) do
      IO.write String.pad_leading("#{i+1}", 2, "0") <> ": ["
      for {nmbr, _j} <- Enum.with_index(game |> Enum.intersperse(", ")) do
        IO.write if (nmbr == ", "), do: nmbr, else: String.pad_leading("#{nmbr}", 2, " ")
      end
      IO.puts "]"
    end
    :ok
  end

  # Very simple error processing. 
  defp error(msg) do
    Logger.error(msg)
  end
end
