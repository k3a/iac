#!/usr/bin/env ruby
# NOAA IAC ('fleetcode') parsing and drawing code
# Written in Ruby by K3A (www.K3A.me)
# Based on zyGrib source code https://github.com/Don42/zyGrib/
# Thanks zyGrib developers for implementing the parsing code!

=begin
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

require 'fileutils'
require 'rvg/rvg'
require 'proj4'
include Magick

IAC_ANALYSE=0		
IAC_FORECAST=1
IAC_UNKNOWN=2

POS_lalalolok_NORTH=0
POS_lalalolok_SOUTH=1
POS_lalalolok_EQUAT=2
POS_iiiD1s1=3
POS_Qlalalolo=4

IAC_FRONT_STATIONARY=0
IAC_FRONT_COLD=1
IAC_FRONT_WARM=2
IAC_FRONT_OCCLUSION=3
IAC_FRONT_INSTABILITY_LINE=4
IAC_FRONT_INTERTROPICAL=5
IAC_FRONT_CONVERGENCE_LINE=6
IAC_FRONT_UNKNOWN=7

# output directory
$DIR = "/home/web/data/"
# uncomment to download data from NOAA
# Please don't download frequently! Cache the file locally and download only when needed!
#`wget -O /tmp/.sana.txt "http://weather.noaa.gov/pub/data/raw/as/asxx21.egrr..txt"`

def is_fleetChar(c)
	c =~ /[0-9a-zA-Z\/]/
end

def readAndSplitLine(line)
	vec = []
	return vec if line.length < 5

	acceptAllChars = false
	acceptAllChars = true if (line[0,6] == "ASXX21" || line[0,6] == "FSXX21")

	vec << "empty" if (line[0,5]=="     ")
	
	str = ""
	line.each_char do |c|
		if ( (acceptAllChars && (c != ' '))  || is_fleetChar(c))
			str += c
		elsif (c == ' ' && str!="" && (acceptAllChars || str.length == 5))
			vec << str
			str = ""
		end
	end

	if (str != "" && (acceptAllChars || str.length == 5)) 
		vec << str
		str = ""
	end

	vec
end

def decodeDataLine_header_NOAA(vline)
	is_NOAA_File = false
	ok = false

	if (vline[1]=="EGRR" && (vline[0]=="ASXX21" || vline[0]=="FSXX21") )
		@sday  = vline[2][0,2]
		@shour = vline[2][2,2]
		@smin  = vline[2][4,2]
		ok = true
		ok = false if (ok && (@sday !~ /[0-9]+/ || !(@sday.to_i>=0 && @sday.to_i<=31) ))
		ok = false if (ok && (@shour !~ /[0-9]+/ || !(@shour.to_i>=0 && @shour.to_i<24) ))
		ok = false if (ok && (@smin !~ /[0-9]+/ || !(@smin.to_i>=0 && @smin.to_i<60) ))
	end

	@is_NOAA_File = ok;
end

def decodeDataLine_preamble(vline)
	@ok = true
	if (vline.length < 3)
		@ok = false
		return
	elsif (vline.length == 3 && vline[0]=="10001" && vline[1][0,3] == "333")
		@iacFileType = IAC_ANALYSE;
	elsif (vline.length == 4 && vline[0]=="65556" && vline[1][0,3] == "333")
		@iacFileType = IAC_FORECAST;
		sdel = vline[3][3,2]
		@ok = false if sdel !~ /[0-9]+/
		@iacFileValidHour = sdel.to_i
	else
		@ok = false
	end

	if @ok
		x1x1 = vline[1][3,2]
		if (x1x1 == "00")  
			@yyyyyPositionMode = POS_lalalolok_NORTH;
		elsif (x1x1 == "11")  
			@yyyyyPositionMode = POS_lalalolok_SOUTH;
		elsif (x1x1 == "22")  
			@yyyyyPositionMode = POS_lalalolok_EQUAT;
		elsif (x1x1 == "66")  
			@yyyyyPositionMode = POS_iiiD1s1;
		elsif (x1x1 == "88")  
			@yyyyyPositionMode = POS_Qlalalolo;
		else 
			@ok = false
		end
	end
end

def readPosition(word)
	lonEast_above_100 = false;
	lonWest_above_100 = false;
	lat = lon = 0
	xmin = xmax = 0
	ymin = ymax = 0
	
	if ( @yyyyyPositionMode == POS_lalalolok_NORTH || @yyyyyPositionMode == POS_lalalolok_SOUTH || @yyyyyPositionMode == POS_lalalolok_EQUAT )
		lala = word[0,2]
		lolo = word[2,2]
		kstr = word[4,1]

		return false if kstr !~ /[0-9]+/
		return false if lala !~ /[.0-9]+/
		return false if lolo !~ /[.0-9]+/

		k = kstr.to_i
		lat = lala.to_f
		lon = lolo.to_f

		case k
		when 1,6
			lat += 0.5
		when 2,7
			lon += 0.5
		when 3,8
			lat += 0.5
			lon += 0.5
		end

		if (k < 5) 
			lon =  - lon - 100 if (lonWest_above_100)
		else 
			if (lonEast_above_100)
				lon =  lon + 100
		 	else
		 		lon = - lon
			end
		end
		
	#puts "pos: k=#{k}  #{lat}  #{lon}"
	elsif (@yyyyyPositionMode == POS_iiiD1s1) 
		return false
	elsif (@yyyyyPositionMode == POS_Qlalalolo) 
		return false
	else 	# unknown postion mode
		return false;
	end

	ymin = lat if (ymin > lat)
	ymax = lat if (ymax < lat)
	xmin = lon if (xmin > lon)
	xmax = lon if (xmax < lon)

	{'lat'=>lat, 'lon'=>lon}
end

def decodeDataLine_sec_0(vline)
	lon = lat = 0

	vline.shift if vline[0][0,1] == "9" # ignore code '9NNSS'
	return if vline.length == 0

	if vline.length >= 2 && (vline[0][0,2]=="81" || vline[0][0,2]=="85")
		pt = vline[0][1,1]	# table 3152
		pc = vline[0][2,1]	# table 3133
		pp = vline[0][3,2]	# PP = pressure on 2 digits

		pr = pp.to_i
		pr += 900 if pr >= 50
		pr += 1000 if pr < 50
		if pt == "1" # LOW pressure
			p = readPosition(vline[1])
			@list_HighLowPressurePoints << ["L", p['lat'], p['lon'], pr] if p
		elsif pt == "5"
			p = readPosition(vline[1])
			@list_HighLowPressurePoints << ["H", p['lat'], p['lon'], pr] if p
		end
	elsif (vline[0][0,2] == "83")	# code='83///' : pressure troughline
	end

	#puts @list_HighLowPressurePoints.inspect
end

def createFront(cmd)
	type = IAC_FRONT_UNKNOWN
	return {} if cmd !~ /[0-9]+/
	
	t = cmd[2,1].to_i
	case t
	when 0,1
		type = IAC_FRONT_STATIONARY
	when 2,3
		type = IAC_FRONT_WARM
	when 4,5
		type = IAC_FRONT_COLD
	when 6
		type = IAC_FRONT_OCCLUSION
	when 7
		type = IAC_FRONT_INSTABILITY_LINE
	when 8
		type = IAC_FRONT_INTERTROPICAL
	when 9
		type = IAC_FRONT_CONVERGENCE_LINE
	end

	return {'type'=>type, 'points'=>[]}
end

def decodeDataLine_sec_1_Fronts(vline)
	lat = lon = 0
	
	vline.shift if (vline[0][0,1] == "9")   # ignore code '9NNSS'
	return if (vline.length == 0) 

	if (vline.length>=2 && (vline[0][0,2]=="66"))
		currentFront = createFront(vline[0])
		@currentFrontIdx = @list_Fronts.length
		@list_Fronts << currentFront
		vline.shift

		vline.each do |v|
			p = readPosition(v)
			@list_Fronts[@currentFrontIdx]['points'] << [p['lat'],p['lon']] if p
		end
	elsif (vline[0] == "empty")	#  front continued
		if (@currentFrontIdx != nil)
			vline.shift # from index 1
			vline.each do |v| 
				p = readPosition(v)
                @list_Fronts[@currentFrontIdx]['points'] << [p['lat'],p['lon']] if p
            end
		end
	else 
		@currentFrontIdx = nil
	end
end

def createIsobar(val)
	return {'value'=>val.to_i, 'points'=>[]}
end

def decodeDataLine_sec_2_Isobars(vline)
	lat = lon = 0

	vline.shift if (vline[0][0,1] == "9")   # ignore code '9NNSS'
	return if (vline.length == 0)

	if (vline.length>=2 && (vline[0][0,2]=="44"))
		val = vline[0][2,3].to_i
		val += 1000 if val < 500 # 44020->1020hPa

		currentIsobar = createIsobar(val)
		@currentIsobarIdx = @list_Isobars.length
		@list_Isobars << currentIsobar
		vline.shift

		vline.each do |v|
				p = readPosition(v)
				@list_Isobars[@currentIsobarIdx]['points'] << [p['lat'],p['lon']] if p
		end
	elsif (vline[0] == "empty")     #  Isobar continued
		if (@currentFrontIdx != nil)
			vline.shift # from index 1
			vline.each do |v| 
				p = readPosition(v)
				@list_Isobars[@currentIsobarIdx]['points'] << [p['lat'],p['lon']] if p
			end
		end
	else
			@currentIsobarIdx = nil
	end
end

def decodeDataLine(vline)
	case @currentSECTION
	when 0
		decodeDataLine_sec_0(vline);
	when 1
		decodeDataLine_sec_1_Fronts(vline);
	when 2
		decodeDataLine_sec_2_Isobars(vline);
	end
end

def decodeLine(vline)
	return if vline.length == 0

	if (vline.length >= 3 && (vline[0]=="ASXX21" || vline[0]=="FSXX21") )
		decodeDataLine_header_NOAA(vline);
	elsif (vline.length == 3 && vline[0]=="ASPS20")
  		# Fiji Fleet codes from NOAA
		decodeDataLine_header_NOAA (vline);
	elsif (vline[0].length != 5) 
		return;	# not a fleet code
	end

	code = vline[0].to_i

	if (vline.length == 1)	# one code -> section start
		case code
		when 99900 # High/Low pressure
			@currentSECTION = 0
		when 99911 # Fronts
			@currentSECTION = 1
		when 99922 # Isobars
			@currentSECTION = 2
		else
			@currentSECTION = -1
		end
	else 
		if (code == 10001 || code == 65556)
			decodeDataLine_preamble (vline)
		else
			decodeDataLine(vline)
		end
	end

    decodeDataLine(vline) if (vline[0] == "empty")
		
end


#readIacFileContent
iacFileType  = IAC_UNKNOWN;
is_NOAA_File = false;
ok = true;
endOfFile   = false;
currentSECTION = -1;
xmin = ymin =  1e20;
xmax = ymax = -1e20;
currentTroughLine = 0;

@list_HighLowPressurePoints = []
@list_Fronts = []
@currentFrontIdx = nil
@list_Isobars = []
@currentIsobarIdx = nil

File.read("/tmp/.sana.txt").each_line do |l|
	l.gsub!(/[\n\r]+/, '')
	larr = readAndSplitLine l
	decodeLine larr if larr.length > 0
end

puts "Not a NOAA file!" if !@is_NOAA_File
term = "#{@sday}#{@shour}#{@smin}"
puts term

#puts @list_HighLowPressurePoints.inspect
#puts @list_Fronts.inspect
#puts @list_Isobars.inspect

$proj = Proj4::Projection.new("+proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +a=6378137 +b=6378137 +to_meter=2000")
# convert lat lon in WGS84 to Pixel position in the image
def transform(latlon, relativeToImage=true)
#	`echo "#{latlon[1]} #{latlon[0]}" | proj +proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +a=6378137 +b=6378137 +to_meter=2000 -f "%.6f"`.split(/\s+/).map{ |v| v.to_f }
	src = Proj4::Point.new(latlon[1]*Proj4::DEG_TO_RAD, latlon[0]*Proj4::DEG_TO_RAD);
	tar = $proj.forward(src)
	loc = [tar.x, tar.y]
	if (relativeToImage)
		loc[0] -= @bmin[0]
		loc[1] = @bhei - (loc[1]-@bmin[1])
	end
	loc
end
@bmin = transform([34.016837,-18.151982], false)
@bmax = transform([58.171081,28.605831], false)
@bwid = @bmax[0]-@bmin[0]
@bhei = @bmax[1]-@bmin[1]

RVG::dpi = 72
rvg = RVG.new(@bwid,@bhei) do |canvas|
	# ISOBARS
    @list_Isobars.each do |i|
        tarr = i['points'].map {|p| transform(p)}
        canvas.polyline( *tarr.flatten ).styles(:fill=>'none', :stroke=>'gray', :stroke_width=>1)
		#path = RVG::PathData.new
		#path.smooth_quadratic_curveto(true, *tarr.flatten)
		#path = "M100,200 C100,100 250,100 250,200 S400,300 400,200"
		#canvas.path(path.to_s)#.styles(:fill=>'none', :stroke=>'black', :stroke_width=>1)

		# value
		pnt = tarr[ (tarr.length/2.0).floor.to_i ]
		canvas.rect(50, 20, pnt[0]-25, pnt[1]-10).styles(:fill=>'white', :stroke=>'black', :stroke_width=>1)
		canvas.text(pnt[0]+23, pnt[1]+7, i['value'].to_s).styles(:text_anchor=>'end',:font_size=>18,
					:font_family=>'DejaVu Sans', :fill=>'black', :stroke=>'none')
    end

	# FRONTS
	@list_Fronts.each do |f|
		tarr = f['points'].map {|p| transform(p)}
		case f['type']
		when IAC_FRONT_COLD
			stroke = 'blue'
		when IAC_FRONT_WARM
			stroke = 'red'
		when IAC_FRONT_OCCLUSION
			stroke = 'magenta'
		else
			stroke = 'black'
		end
		canvas.polyline( *tarr.flatten ).styles(:fill=>'none', :stroke=>stroke, :stroke_width=>2)
	end

	# PRESS SYS
	@list_HighLowPressurePoints.each do |p|
		pos = transform([p[1], p[2]])
		canvas.g do |grp|
			grp.text(pos[0]-20, pos[1], p[0]).styles(:text_anchor=>'end',:font_size=>35,
					:font_family=>'DejaVu Sans', :fill=>'white')
			grp.text(pos[0]-9, pos[1]+20, p[3]).styles(:text_anchor=>'end',:font_size=>18,
                    :font_family=>'DejaVu Sans', :fill=>'white')
		end
	end
	
	# INFO
	canvas.text(@bwid-5, 80,"SFC Analysis #{@sday}th #{@shour}:#{@smin}").styles(:text_anchor=>'end', :font_size=>40,
                   :font_family=>'DejaVu Sans', :fill=>'white', :stroke=>'none')
end

rvg.draw.alpha(Magick::ActivateAlphaChannel)
rvg.draw.write("/tmp/.sana.png")
`/usr/bin/convert /tmp/.sana.png png8:#{$DIR}/sana_#{term}.png`
FileUtils.ln_s("#{$DIR}/sana_#{term}.png", "#{$DIR}/sana.png", :force => true)


