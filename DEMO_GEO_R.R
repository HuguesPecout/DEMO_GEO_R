################################################################################
#                                                                              #
#                          Traitement de l'IG avec R                           #
#                                                                              #
################################################################################

################################################################################
# Chargement des librairies
################################################################################

# install.packages("sf")
# install.packages("mapsf")
# install.packages("mapview")
# install.packages("maptiles")
# install.packages("osrm")
# install.packages("tidygeocoder")
# install.packages("spatstat")
# install.packages("osmdata")
# install.packages("terra")

library(sf)
library(maptiles)
library(osmdata)
library(tidygeocoder)
library(spatstat)
library(mapsf)
library(mapview)
library(terra)
library(osrm)
library(mapiso)


################################################################################
# A. Import & récupération de données
################################################################################

####################### 1. Import de données stockées en local #################

# Lister les couches géographiques d'un fichier GeoPackage
st_layers("data/TAIS_workshop.gpkg")

## Import des données géographiques en objet sf
commune <- st_read(dsn = "data/TAIS_workshop.gpkg", layer = "commune")
paris <- st_read(dsn = "data/TAIS_workshop.gpkg", layer = "paris")
# road <-st_read(dsn = "data/TAIS_workshop.gpkg", layer = "troncon_routier")
railway <-st_read(dsn = "data/TAIS_workshop.gpkg", layer = "voie_ferree")
water <-st_read(dsn = "data/TAIS_workshop.gpkg", layer = "surface_hydro")

# Affichage des couches importées
mf_map(paris, col = "grey90", border = NA)
mf_map(railway, col = "#3d3d3d30", add = TRUE)
# mf_map(road, col = "#c1bfbf40", add = TRUE)
mf_map(water, col = "#3d8ed260", border = "#3d8ed260", add = TRUE)
mf_map(commune, border = "grey50", cex = 0.2, col = NA, add = TRUE)


############################ 2. Récupération de données OSM ####################

# Calcul d'une emprise (Paris + 1000m)
emprise <- paris |> 
            st_transform(crs = "EPSG:4326")|>
            st_buffer(dist = 1000) |>
            st_bbox() 


######### 2.A Extraction d'une tuile OSM (fond de carte)
tiles <- get_tiles(x = emprise, 
                   project = FALSE, 
                   crop = TRUE, 
                   zoom = 13, 
                   cachedir = "cache")


# Affichage d'une tuile raster
mf_raster(tiles)



######### 2.B Extraction de données vectorielles OSM

# Définition d'une bounding box (emprise Paris)
q <- opq(bbox = emprise, osm_types = "node")

# Extraction des restaurants
req <- add_osm_feature(opq = q, key = 'amenity', value = "restaurant")
res <- osmdata_sf(req)
resto <- res$osm_points

# Re-projection
resto  <- st_transform(resto , crs = "EPSG:3857")

# Affichage
mf_raster(tiles)
mf_map(resto, cex= 0.2, add = TRUE)



######### 2.C Géocodage d'adresse (= point vectoriel)

# Construction d'un data.frame contenant des adresses
stade <- data.frame(nom = c("Parc des Princes", "Stade Charlety"),
                    equipe = c("PSG", "Paris FC"),
                    rue = c("24 Rue du Commandant Guilbaud, 75016 Paris", 
                            "99 Boulevard Kellermann, 75013 Paris"))

# Géocodage (BD Nominatim - OSM)
stade_geo <- geocode(.tbl = stade, address = "rue", quiet = TRUE)

# Transformation du tableau en objet sf
# Utilisation des latitudes & longitudes
stade_sf <- st_as_sf(stade_geo , coords = c("long", "lat"), crs = 'EPSG:4326')

# Affichage interactif
mapview(stade_sf)


######### 2.D Affichage de toutes les données récupérées

# Consulter la projection d'une couche
st_crs(resto)

# Re-projection
tiles_2154 <- project(x = tiles, y = "EPSG:2154")
resto_2154 <- st_transform(resto , crs = "EPSG:2154")
stade_2154 <- st_transform(stade_sf , crs = "EPSG:2154")

# Affichage de toutes les données
mf_raster(tiles_2154)
mf_map(railway, col = "#3d3d3d30", add= TRUE)
# mf_map(road, col = "#c1bfbf40", add= TRUE)
mf_map(water, col = "#3d8ed260", border = "#3d8ed260", add= TRUE)
mf_map(resto_2154, col = "red3", cex= 0.17, add= TRUE)
mf_map(stade_2154, col = "black", cex=1.2, pch = 15, add= TRUE)
mf_map(commune, border = "grey50", cex = 0.2, col = NA, add= TRUE)



################################################################################
# B. Exploration I - répartition des restaurants
################################################################################

################# 1. Nombre de restaurants à proximité du Parc des Princes ? ###

# Calcul d'un buffer de 500m
PSG_buff500m <- st_buffer(stade_2154[1,], 500)

# Intersection entre les restaurants et le buffer de 500m
inters_resto_buff <- st_intersection(resto_2154, PSG_buff500m)

# Nombre de restaurants dans un rayon de 500m ?
nrow(inters_resto_buff)


################# 2. Densité de restaurants - Méthode grille régulière #########

# Création d'une grille régulière (500m de coté) sur Paris
grid <- st_make_grid(paris, cellsize = 500, square = TRUE)

# Transformation de la grille (sfc) en obejt sf
grid <- st_sf(ID = 1:length(grid), geometry = grid)

# Affichage de la grille
mf_map(paris)
mf_map(grid, col = NA, add = TRUE)

# Récupération du carreau d'appartenance de chaque restaurant
grid_resto <- st_intersects(grid, resto_2154, sparse = TRUE)

# Comptage du nombre de restaurants dans chacun des carreaux
grid$nb_resto <- lengths(grid_resto)

# Découpage de la grille par les limites de Paris
grid_paris <- st_intersection(grid, st_union(paris))

# Affichage de la grille
mf_map(grid_paris, col = NA)

# Enregistrement de la grille en "dur" dans le fichier geopackage
st_write(obj = grid_paris, 
         dsn = "data/TAIS_workshop.gpkg", 
         layer = "grid500m_paris", 
         delete_layer = TRUE)


####################### 3. Cartographie thématique exploratoire ################

# 1. Carte choroplèthe (aplat de couleur)
mf_raster(tiles_2154)
mf_map(grid_paris, 
       var = "nb_resto", 
       type = "choro",
       breaks = "jenks",
       border = "white",
       pal = "Teal", 
       alpha = .8,
       leg_pos = "topright",
       leg_val_rnd = 1,
       leg_title = paste0("Nombre de restaurants\n",
                          "Carroyage de 500m\n"), add = TRUE)

# 2. Carte en symbole proportionnel 
mf_raster(tiles_2154)
mf_map(grid_paris, add = TRUE, col = NA)
mf_map(grid_paris, 
       var = "nb_resto", 
       type = "prop",
       border = "white",
        inches = 0.1,
       leg_pos = "topright",
       leg_title = paste0("Nombre de restaurants\n",
                          "Carroyage de 500m\n"), add = TRUE)

# 3. Carte combinée (symbole proportionnel & aplat de couleur)
mf_raster(tiles_2154)
mf_map(grid_paris, add = TRUE, col = NA)
mf_map(grid_paris, 
       var = c("nb_resto", "nb_resto"), 
       type = "prop_choro",
       pal = "Teal", 
       breaks = "quantile",
       border = "white",
       inches = 0.1,
       leg_pos = "topright",
       leg_title = paste0("Nombre de restaurants\n",
                          "Carroyage de 500m\n"), add = TRUE)



##################### 4. Densité de restaurants - Méthode lissage KDE ##########

######### 4.A Construction d'un objet ppp (spatstat) à partir du semi de point
p <- as.ppp(X = st_coordinates(resto_2154), 
            W = as.owin(st_bbox(resto_2154)))

# Calcul densité par lissage 
ds <- density.ppp(x = p, sigma = 150, eps = 10, positive = TRUE)

# Affichage du résultat
plot(ds)

# Calcul densité de restaurants par hectare
r <- rast(ds) * 100 * 100

# Ajout d'une projection
crs(r) <- st_crs(resto_2154)$wkt

# Affichage
plot(r)


######### 4.B Conversion du raster en ploygone par plage de valeur

# Création d'un vecteur contenant les bornes de classe
maxval <- max(values(r))
bks <-  c(seq(0, floor(maxval), 1), maxval)

# Transformation du raster en polygones à partir de la discrétisation choisie
iso_dens <- mapiso(r, breaks = bks)# Suppression de la première classe ([0, 1[) ou le nb de retsaurant < 1
iso_dens <- iso_dens[-1, ]

# Affichage simple du résultat
mf_raster(tiles_2154)
mf_map(iso_dens, 
       var = "isomin", 
       type = "choro",
       breaks = bks[-1], 
       border = "white",
       lwd = 0.1,
       pal = "Teal", 
       alpha = .6,
       leg_pos = "topright",
       leg_val_rnd = 1,
       leg_title = paste0("Densité de restaurants\n",
                          "par hectare, dans un\n",
                          "voisinage gaussien\n", 
                          "(σ = 150m)"), add = TRUE)



# Cartographie avancée du résultat
mf_map(paris, col = "grey90", border = NA)
mf_map(railway, col = "#3d3d3d30", add = TRUE)
# mf_map(road, col = "#c1bfbf40", add = TRUE)
mf_map(water, col = "#3d8ed260", border = "#3d8ed260", add = TRUE)
mf_map(commune, border = "grey40", lwd = 0.2, col = NA, add = TRUE)
mf_map(iso_dens, 
       var = "isomin", 
       type = "choro",
       breaks = bks[-1], 
       border = "white", 
       lwd = 0.1,
       pal = "Teal", 
       alpha = .7,
       leg_pos = "topright", 
       leg_size = 0.8,
       leg_frame = TRUE,
       leg_box_border = FALSE,
       leg_bg = "#FFFFFF99",
       leg_val_rnd = 1,
       leg_title_cex = 0.6,
       leg_title = paste0("Nombre de restaurants\npar hectare, voisinage\n",
                          "gaussien (σ = 150m)\n"), add = TRUE)

mf_map(stade_2154, col = "black", cex=0.8, pch = 15, add = TRUE)

mf_annotation(x = stade_2154[1,], 
              txt = stade_2154$nom[1], 
              halo = TRUE, 
              cex = 0.6,pos = "topright")


mf_legend(val_cex = 0.6, 
          title = NA, 
          size = 0.6,
          type = "typo", 
          val = c("railway", "road", "water"),
          pal = c("grey60", "grey75", "steelblue2"), 
          pos = "topleft")

mf_layout(title = "Densité de restaurants à Paris",
          credits = "",
          arrow = FALSE, 
          scale = TRUE)

mf_credits("Auteurs : H. Pecout\nSources : BD CARTO, IGN 2024 - OpenStreetMap 2024",
           cex = 0.5)




################################################################################
# C. Exploration II - Accessibilité aux restaurants
################################################################################

################## 1. Accessibilité aux zones denses de restaurants ? ##########


# Extraction des zones les plus denses (polygones)
zone_dense <- iso_dens[iso_dens$isomax == max(iso_dens$isomax), ]
# Multipolygon - > plusieurs polygones
zones_denses <- st_cast(zone_dense, "POLYGON")

# Extraction des centroïdes des zones séléctionnées
centres_denses <- st_centroid(zones_denses)

# Ajout de Nom au centres
centres_denses$name <- LETTERS[1:3]


# Affichage zones denses
mf_init(paris)
mf_map(commune, border = "grey40", lwd = 0.2, col = NA, add= TRUE)
mf_map(iso_dens, var = "isomin", type = "choro", add = TRUE)
mf_map(stade_2154, col = "black", cex=0.8, pch = 15, add = TRUE)
mf_label(centres_denses, var = "name",col = "red", cex = 1, halo = TRUE)

# Calcul matrice de distance euclidienne
mat_dist_eucli <- st_distance(x = stade_2154, y = centres_denses)
rownames(mat_dist_eucli) <- stade_2154$nom

# Calcul de la matrice de distance par la route
mat_dist_road <- osrmTable(src = stade_2154,
                           dst = centres_denses,
                           osrm.profile = "car",
                           measure = c('duration', 'distance'))


# Changement noms de lignes des matrices
rownames(mat_dist_road$durations) <- stade_2154$nom
rownames(mat_dist_road$distances) <- stade_2154$nom

# Changement noms des colonnes des matrices
colnames(mat_dist_road$durations) <- centres_denses$name
colnames(mat_dist_road$distances) <- centres_denses$name

# Affichage matrice
mat_dist_road

######################### 2. Calcul d'itinéraire avec OSRM #####################

from <- stade_2154[1, ]
A <- centres_denses[centres_denses$name == "A", ]
B <- centres_denses[centres_denses$name == "B", ]
C <- centres_denses[centres_denses$name == "C", ]

# Itinéraire PSG -> zone dense la plus proche
route_A <- osrmRoute(src = from, dst = A)
route_B <- osrmRoute(src = from, dst = B)
route_C <- osrmRoute(src = from, dst = C)


# Affichage de l'itinéraire récupéré

# Affichage
mf_theme(mar = c(0,0,1.2,0))
mf_raster(tiles_2154)
mf_map(iso_dens, 
       var = "isomin", 
       type = "choro",
       breaks = bks[-1], 
       border = "white",
       pal = "Teal", 
       alpha = .5,
       leg_pos = NA, 
       add = TRUE)

# Affichage de l'itinéraire récupéré
mf_map(route_A, col = "grey10", lwd = 4, add = T)
mf_map(route_A, col = "grey90", lwd = 0.8, add = T)

mf_map(route_B, col = "grey10", lwd = 4, add = T)
mf_map(route_B, col = "grey90", lwd = 0.8, add = T)

mf_map(route_C, col = "grey10", lwd = 4, add = T)
mf_map(route_C, col = "grey90", lwd = 0.8, add = T)

# Affichage PSG
mf_map(from, col = "red", cex= 2, add = T)


# Ajout d'une annotation
mf_annotation(x = from, 
              txt = from$nom, 
              halo = TRUE, 
              pos = "bottomright", 
              cex = 0.7)

# Nom des centres
mf_label(centres_denses, var = "name",col = "red", cex = 1, halo = TRUE)


