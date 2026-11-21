#include "noshi_geo.h"
#include "noshi_messages.h"
#include "noshi_bots.h"
#include "noshi_tl_ids.h"
#include "test_util.h"
#include <math.h>

static void projection(void) {
    const double points[][2] = {{0,0},{55.03,82.92},{-33.87,151.21},{85,179.99},{-85,-179.99},{90,180}};
    for (size_t i = 0; i < sizeof(points)/sizeof(points[0]); ++i) {
        double x,y,lat,lon;
        CHECK_EQ_INT(noshi_map_project(points[i][0],points[i][1],&x,&y),NOSHI_OK);
        CHECK(x>=0 && x<1 && y>=0 && y<=1);
        CHECK_EQ_INT(noshi_map_unproject(x,y,&lat,&lon),NOSHI_OK);
        CHECK(fabs(lat-fmax(-NOSHI_MAP_MAX_LATITUDE,fmin(NOSHI_MAP_MAX_LATITUDE,points[i][0])))<1e-8);
        CHECK(fabs(lon-(points[i][1]==180 ? -180 : points[i][1]))<1e-8);
    }
    double x=1,y=1;
    CHECK_EQ_INT(noshi_map_project(NAN,0,&x,&y),NOSHI_E_ARG);
    CHECK(x==0 && y==0);
    CHECK_EQ_INT(noshi_map_project(0,181,&x,&y),NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_map_unproject(INFINITY,0,&x,&y),NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_map_unproject(-0.25,2,&x,&y),NOSHI_OK);
    CHECK(fabs(y-90)<1e-8 && fabs(x+NOSHI_MAP_MAX_LATITUDE)<1e-8);
}

static void visible_tiles(void) {
    noshi_map_tile tiles[NOSHI_MAP_MAX_TILES];
    size_t count=99;
    CHECK_EQ_INT(noshi_map_tiles(0,179.99,3,320,480,tiles,NOSHI_MAP_MAX_TILES,&count),NOSHI_OK);
    CHECK(count>0 && count<=6);
    int wraps=0;
    for(size_t i=0;i<count;++i) {
        CHECK(tiles[i].x<8 && tiles[i].y<8 && tiles[i].zoom==3);
        CHECK(tiles[i].left<320 && tiles[i].left+tiles[i].side>0);
        CHECK(tiles[i].top<480 && tiles[i].top+tiles[i].side>0);
        if(tiles[i].x==0) wraps=1;
    }
    CHECK(wraps);
    CHECK_EQ_INT(noshi_map_tiles(90,0,2,768,1024,tiles,NOSHI_MAP_MAX_TILES,&count),NOSHI_OK);
    for(size_t i=0;i<count;++i) CHECK(tiles[i].y<4);
    CHECK_EQ_INT(noshi_map_tiles(0,0,19,4096,4096,tiles,NOSHI_MAP_MAX_TILES,&count),NOSHI_E_LIMIT);
    CHECK_EQ_INT(count,0);
    CHECK_EQ_INT(noshi_map_tiles(0,0,2,320,480,tiles,1,&count),NOSHI_E_LIMIT);
    CHECK_EQ_INT(count,0);
    CHECK_EQ_INT(noshi_map_tiles(0,0,NAN,320,480,tiles,64,&count),NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_map_tiles(0,0,20,320,480,tiles,64,&count),NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_map_tiles(0,0,1,0,480,tiles,64,&count),NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_map_tiles(0,0,1.5,320,480,tiles,64,&count),NOSHI_OK);
    CHECK(fabs(tiles[0].side-256*sqrt(2))<1e-8);
}

static void protocol(void) {
    noshi_arena arena;
    noshi_arena_init(&arena,1024*1024);
    noshi_tl_value *geo=noshi_tl_new_obj(&arena,"geoPoint");
    CHECK_EQ_INT(noshi_tl_set_f64(&arena,geo,"lat",55.03),NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_f64(&arena,geo,"long",82.92),NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i64(&arena,geo,"access_hash",1),NOSHI_OK);
    noshi_tl_value *media=noshi_tl_new_obj(&arena,"messageMediaVenue");
    CHECK_EQ_INT(noshi_tl_set(media,"geo",geo),NOSHI_OK);
    const char *keys[]={"title","address","provider","venue_id","venue_type"};
    const char *values[]={"park","street","foursquare","123","outdoors"};
    for(size_t i=0;i<5;++i) CHECK_EQ_INT(noshi_tl_set_str(&arena,media,keys[i],values[i]),NOSHI_OK);
    noshi_media_info info;
    noshi_media_classify(media,&info);
    CHECK_EQ_INT(info.kind,NOSHI_PREVIEW_LOCATION);
    CHECK(info.location.valid && info.location.venue);
    CHECK(!strcmp(info.location.title,"park"));
    CHECK(fabs(info.location.latitude-55.03)<1e-8);
    noshi_peer_ref peer={0};
    peer.kind=1;peer.id=123;peer.access_hash=456;
    noshi_tl_value *request=NULL;
    CHECK_EQ_INT(noshi_send_location_request(&arena,&peer,&info.location,789,&request),NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request,"media"),NOSHI_TL_ID_inputMediaVenue));
    noshi_writer writer;
    noshi_writer_init(&writer,2048);
    CHECK_EQ_INT(noshi_tl_encode(request,&writer,NULL),NOSHI_OK);
    CHECK(writer.len>0);
    noshi_writer_free(&writer);
    info.location.venue=0;
    CHECK_EQ_INT(noshi_send_location_request(&arena,&peer,&info.location,789,&request),NOSHI_OK);
    CHECK(noshi_tl_is(noshi_tl_get(request,"media"),NOSHI_TL_ID_inputMediaGeoPoint));
    info.location.latitude=NAN;
    CHECK_EQ_INT(noshi_send_location_request(&arena,&peer,&info.location,789,&request),NOSHI_E_ARG);
    CHECK(request==NULL);
    CHECK_EQ_INT(noshi_tl_set_f64(&arena,geo,"lat",91),NOSHI_OK);
    noshi_media_classify(media,&info);
    CHECK(!info.location.valid);
    CHECK_EQ_INT(noshi_geo_read(NULL,NULL,&info.location),NOSHI_E_MALFORMED);
    CHECK(!info.location.valid);
    CHECK_EQ_INT(noshi_tl_set_f64(&arena,geo,"lat",55.03),NOSHI_OK);
    char long_title[302];
    for (size_t i=0;i<300;i+=2) { long_title[i]=(char)0xd0; long_title[i+1]=(char)0x90; }
    long_title[300]=0;
    CHECK_EQ_INT(noshi_tl_set_str(&arena,media,"title",long_title),NOSHI_OK);
    noshi_media_classify(media,&info);
    CHECK(info.location.valid && info.location.venue);
    CHECK_EQ_INT(strlen(info.location.title),126);
    noshi_tl_value *empty=noshi_tl_new_obj(&arena,"geoPointEmpty");
    CHECK_EQ_INT(noshi_geo_read(empty,NULL,&info.location),NOSHI_E_MALFORMED);
    noshi_tl_value *inline_message=noshi_tl_new_obj(&arena,"botInlineMessageMediaVenue");
    CHECK_EQ_INT(noshi_tl_set(inline_message,"geo",geo),NOSHI_OK);
    for(size_t i=0;i<5;++i) CHECK_EQ_INT(noshi_tl_set_str(&arena,inline_message,keys[i],values[i]),NOSHI_OK);
    noshi_tl_value *item=noshi_tl_new_obj(&arena,"botInlineResult");
    CHECK_EQ_INT(noshi_tl_set_str(&arena,item,"id","venue-1"),NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_str(&arena,item,"type","venue"),NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(item,"send_message",inline_message),NOSHI_OK);
    noshi_tl_value *items=noshi_tl_new_vec(&arena,1);
    CHECK_EQ_INT(noshi_tl_vec_set(items,0,item),NOSHI_OK);
    noshi_tl_value *answer=noshi_tl_new_obj(&arena,"messages.botResults");
    CHECK_EQ_INT(noshi_tl_set_i64(&arena,answer,"query_id",12),NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set_i32(&arena,answer,"cache_time",30),NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_set(answer,"results",items),NOSHI_OK);
    noshi_inline_page page;
    noshi_inline_result row;
    size_t count=0;
    CHECK_EQ_INT(noshi_inline_results_parse(answer,&page,&row,1,&count),NOSHI_OK);
    CHECK_EQ_INT(count,1);
    CHECK(row.media.location.valid && row.media.location.venue);
    CHECK(!strcmp(row.media.location.venue_id,"123"));
    CHECK_EQ_INT(noshi_tl_set_f64(&arena,geo,"lat",NAN),NOSHI_OK);
    CHECK_EQ_INT(noshi_inline_results_parse(answer,&page,&row,1,&count),NOSHI_OK);
    CHECK_EQ_INT(count,0);
    noshi_arena_free(&arena);
}

static void png_bounds(void) {
    uint8_t png[33]={137,80,78,71,13,10,26,10,0,0,0,13,'I','H','D','R',0,0,1,0,0,0,1,0};
    CHECK(noshi_map_png_header(png,sizeof(png)));
    CHECK(!noshi_map_png_header(png,23));
    CHECK(!noshi_map_png_header(png,NOSHI_MAP_TILE_BYTES_MAX+1));
    CHECK(!noshi_map_png_header(NULL,33));
    png[18]=2; CHECK(!noshi_map_png_header(png,sizeof(png))); png[18]=1;
    png[11]=12; CHECK(!noshi_map_png_header(png,sizeof(png))); png[11]=13;
    png[0]='<'; CHECK(!noshi_map_png_header(png,sizeof(png)));
}

int main(void) {
    projection();visible_tiles();protocol();png_bounds();
    return test_finish("test_geo");
}
