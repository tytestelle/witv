package com.whyun.witv.epg;

import java.util.List;
import java.util.Map;

public class EPGParserFactory {
    public static EPGParser getParser(String format) {
        // TODO: 根据 format 返回对应的解析器实现（DIYP、百川、超级TV、XMLTV）
        // 目前返回 null，后续可扩展
        return null;
    }

    public interface EPGParser {
        Map<String, List<EPGProgram>> parse(String data);
    }

    public static class EPGProgram {
        public String title, startTime, endTime, desc;
    }
}
