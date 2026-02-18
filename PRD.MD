# Product Requirements Document (PRD) – Route25

## 1. Project Overview
Route25 is a Flutter-based mobile app that helps commuters in Iloilo City find the correct jeepney route using their current location and destination. It guides users on which jeepney to ride, where to board and drop off, and if transfers are needed, displaying the route visually on a map.

## 2. Target Users
- Students and daily commuters  
- New residents  
- Visitors in Iloilo City  

## 3. Core Features & Functionalities

### 3.1 Location Detection
- Automatically detect user’s current location via GPS  
- Option to manually enter starting point  

### 3.2 Destination Input
- Search bar to type or select destination  
- Autocomplete suggestions from stored stops  

### 3.3 Route Matching
- Checks if a single jeepney route covers origin and destination  
- Determines if a transfer is required between routes  
- Ranks options by shortest distance and fewest transfers  

### 3.4 Route Guidance Display
- Shows jeepney route name/code  
- Boarding and drop-off points  
- Transfer instructions (if needed)  
- Estimated fare  
- Estimated travel distance  

### 3.5 Map Visualization
- Displays selected route on an interactive map with polylines  
- Visual markers for boarding, transfer, and drop-off points  

## 4. Data Requirements
- Database of jeepney routes with:  
  - Route name/code  
  - Ordered list of stops  
  - Geographic coordinates for each stop  
  - Fare per route  

## 5. Technical Requirements
- Mobile frontend: Flutter  
- Backend: Supabase or Firebase  
- Map service: OpenStreetMap / Mapbox for route visualization  
- Route computation logic implemented in backend or frontend  

## 6. Success Criteria
- Users can quickly find routes from origin to destination  
- Accurate route recommendations including transfer points  
- Clear visual representation of route on the map
