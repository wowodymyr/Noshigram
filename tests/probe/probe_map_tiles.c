#include "noshi_https.h"
#include "noshi_geo.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* an explicit integration probe, one world tile, never a host unit test */
int main(int argc, char **argv) {
    if (argc!=2) { fprintf(stderr,"usage: probe_map_tiles roots.pem\n"); return 2; }
    FILE *file=fopen(argv[1],"rb");
    if (!file) return 2;
    if (fseek(file,0,SEEK_END)!=0) { fclose(file);return 2; }
    long length=ftell(file);
    if (length<=0 || length>1024*1024 || fseek(file,0,SEEK_SET)!=0) { fclose(file);return 2; }
    char *roots=malloc((size_t)length);
    if (!roots) { fclose(file);return 2; }
    size_t got=fread(roots,1,(size_t)length,file);
    int closed=fclose(file);
    if (got!=(size_t)length || closed!=0) { free(roots);return 2; }
    const char *hosts[]={"tile.openstreetmap.org"};
    const char *paths[]={"/0/0/0.png"};
    const char *headers[]={"User-Agent: Noshigram/1.3.0-stable (com.noshigram.app; iOS integration probe)","Accept: image/png","Accept-Encoding: identity",NULL};
    int failed=0;
    for (size_t i=0;i<1;++i) {
        noshi_https_request request;
        noshi_https_response response;
        memset(&request,0,sizeof(request));
        request.host=hosts[i];request.path=paths[i];request.port=443;request.headers=headers;
        request.roots_pem=roots;request.roots_len=(size_t)length;request.timeout_ms=12000;
        noshi_status status=noshi_https_get(&request,&response);
        int png=status==NOSHI_OK && response.status==200 && noshi_map_png_header(response.body,response.body_len);
        printf("%s: TLS %s, HTTP %d, %zu bytes, 256x256 PNG header %s\n",hosts[i],noshi_status_name(status),response.status,response.body_len,png ? "yes":"no");
        if (!png) failed=1;
        noshi_https_response_free(&response);
    }
    free(roots);
    return failed;
}
